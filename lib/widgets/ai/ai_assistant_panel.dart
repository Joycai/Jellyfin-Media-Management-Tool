import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/organize_plan.dart';
import '../../services/ai_service.dart';
import '../../services/file_browser_service.dart';
import '../../services/rename_service.dart';
import '../../theme/app_theme.dart';
import '../../services/apply_controller.dart';
import '../../services/history_service.dart';
import '../../services/task_service.dart';
import '../../utils/path_tree.dart';
import '../glass/glass_panel.dart';
import 'organize_preview_dialog.dart';
import '../dialogs/part_dialog.dart';
import '../dialogs/subtitle_dialog.dart';
import '../dialogs/tv_show_dialog.dart';
import '../../services/file_label_service.dart';

/// Right pane: AI reasoning, the proposed target tree, Apply/Edit actions and a
/// usage footer. When idle it shows a short hint.
class AiAssistantPanel extends StatelessWidget {
  const AiAssistantPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ai = context.watch<AiService>();
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final plan = ai.currentPlan;

    return Container(
      decoration: BoxDecoration(
        color: glass.sidebarFill,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(analyzing: ai.isAnalyzing, hasPlan: plan != null),
          Expanded(
            child: (plan == null && !ai.isAnalyzing)
                ? _Idle(configured: ai.isConfigured)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    children: [
                      _ReasoningCard(plan: plan, analyzing: ai.isAnalyzing),
                      if (plan != null && plan.actions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _TargetStructureCard(plan: plan),
                      ],
                    ],
                  ),
          ),
          if (plan != null && plan.actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _confirmApply(context, ai),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        l10n.applyOrganize,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => _edit(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(l10n.edit),
                  ),
                ],
              ),
            ),
          const _Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Row(
              children: [
                Text(
                  l10n.usage,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.tokensLabel(ai.lastTokens),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmApply(BuildContext context, AiService ai) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final browser = context.read<FileBrowserService>();
    final tasks = context.read<TaskService>();
    final history = context.read<HistoryService>();
    final plan = ai.currentPlan!;
    final baseDir = ai.planBaseDir!;
    final totalBytes = await _sumSourceSizes(plan, baseDir);
    if (!context.mounted) return;

    final res = await OrganizePreviewDialog.show(
      context,
      plan: plan,
      baseDir: baseDir,
      totalBytes: totalBytes,
    );
    if (res == null || !res.apply) return;

    final controller = ApplyController(
      plan: plan,
      baseDir: baseDir,
      backup: res.backup,
      totalBytes: totalBytes,
      history: history,
    );
    tasks.startApply(
      controller: controller,
      label: p.basename(baseDir),
      onDone: () {
        final result = controller.result;
        browser.refresh();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.hasFailures
                  ? l10n.applyPartial(result.failed, result.succeeded)
                  : l10n.applyDone(result.succeeded),
            ),
          ),
        );
        // controller stays alive until the task is dismissed so the user can
        // re-open the detail screen post-completion; TaskService.dismiss is
        // the cue to free it. For now keep it — typical tasks are small.
      },
    );
    ai.clearPlan();

    messenger.showSnackBar(SnackBar(content: Text(l10n.tasksApplyStarted)));
  }

  /// Best-effort total byte size of the plan's source files (for the preview's
  /// "N GB" stat). Missing files are skipped. Runs lookups in parallel via
  /// async `length()` so a 400-file plan doesn't freeze the UI on the way to
  /// the preview dialog.
  Future<int> _sumSourceSizes(OrganizePlan plan, String baseDir) async {
    final sizes = await Future.wait(
      plan.actions.map((a) async {
        try {
          final f = File(p.normalize(p.join(baseDir, a.source)));
          if (await f.exists()) return await f.length();
        } catch (_) {}
        return 0;
      }),
    );
    return sizes.fold<int>(0, (sum, n) => sum + n);
  }

  /// Manual fallback: applies a Jellyfin rename rule to the selected file using
  /// the existing dialogs + [RenameService].
  Future<void> _edit(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final browser = context.read<FileBrowserService>();
    final selected = browser.selectedFile;
    if (selected == null || selected.isDirectory) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.selectFileToPreview)));
      return;
    }
    final file = File(selected.path);

    final rule = await showModalBottomSheet<RenameRule>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx)!;
        final isSubtitle =
            FileLabelService.getLabel(p.extension(file.path)) == 'Subtitle';
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_copy),
                title: Text(l.matchFolderName),
                onTap: () => Navigator.pop(ctx, RenameRule.matchFolder),
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: Text(l.renameToFeaturette),
                onTap: () => Navigator.pop(ctx, RenameRule.featurette),
              ),
              ListTile(
                leading: const Icon(Icons.mic),
                title: Text(l.renameToInterview),
                onTap: () => Navigator.pop(ctx, RenameRule.interview),
              ),
              ListTile(
                leading: const Icon(Icons.segment),
                title: Text(l.renameToPart),
                onTap: () => Navigator.pop(ctx, RenameRule.part),
              ),
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(l.renameToTVShow),
                onTap: () => Navigator.pop(ctx, RenameRule.tvShow),
              ),
              if (isSubtitle)
                ListTile(
                  leading: const Icon(Icons.subtitles),
                  title: Text(l.jellyfinSubtitle),
                  onTap: () => Navigator.pop(ctx, RenameRule.subtitle),
                ),
            ],
          ),
        );
      },
    );
    if (rule == null) return;
    if (!context.mounted) return;

    String? extra;
    if (rule == RenameRule.part) {
      extra = await showDialog<String>(
        context: context,
        builder: (_) => const PartDialog(),
      );
      if (extra == null) return;
    } else if (rule == RenameRule.tvShow) {
      final r = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => const TVShowDialog(initialSeason: 1, initialEpisode: 1),
      );
      if (r == null) return;
      extra = r['result'] as String;
    } else if (rule == RenameRule.subtitle) {
      final videos = file.parent
          .listSync()
          .whereType<File>()
          .where(
            (f) => FileLabelService.getLabel(p.extension(f.path)) == 'Video',
          )
          .toList();
      if (videos.isEmpty) return;
      if (!context.mounted) return;
      final r = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SubtitleDialog(
          videoFiles: videos,
          initialLang: 'zh-Hans',
          initialDefault: false,
        ),
      );
      if (r == null) return;
      extra = r['result'] as String;
    }

    try {
      final newName = RenameService.getNewName(file, rule, extra: extra);
      await RenameService.rename(file, newName);
      browser.refresh();
      messenger.showSnackBar(
        SnackBar(content: Text('${p.basename(file.path)} → $newName')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorRenaming(e.toString()))),
      );
    }
  }
}

class _Header extends StatelessWidget {
  final bool analyzing;
  final bool hasPlan;
  const _Header({required this.analyzing, required this.hasPlan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiAssistant,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  analyzing
                      ? l10n.analyzingSelected
                      : (hasPlan ? l10n.analysisComplete : l10n.aiPanelIdle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningCard extends StatelessWidget {
  final OrganizePlan? plan;
  final bool analyzing;
  const _ReasoningCard({required this.plan, required this.analyzing});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final steps = plan?.reasoning ?? const [];

    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.all(16),
      fill: scheme.primary.withValues(alpha: 0.09),
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reasoning.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (analyzing && steps.isEmpty)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.analyzing,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            )
          else
            ...steps.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: const Color(0xFF34C759),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TargetStructureCard extends StatelessWidget {
  final OrganizePlan plan;
  const _TargetStructureCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final lines = buildPathTree(plan.actions.map((a) => a.target).toList());

    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.all(16),
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.targetStructure.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...lines.map(
            (line) => Padding(
              padding: EdgeInsets.only(left: line.depth * 16.0, bottom: 5),
              child: Row(
                children: [
                  Icon(
                    line.isDir
                        ? Icons.folder_rounded
                        : Icons.insert_drive_file_outlined,
                    size: 15,
                    color: line.isDir
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: line.isDir ? null : 'monospace',
                        fontWeight: line.isDir
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  final bool configured;
  const _Idle({required this.configured});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            Text(
              configured ? l10n.aiPanelIdle : l10n.aiNotConfigured,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
    );
  }
}
