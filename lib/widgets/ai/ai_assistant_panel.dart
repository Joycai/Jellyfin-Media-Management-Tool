import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/organize_plan.dart';
import '../../services/ai/ai_service.dart';
import '../../services/file_browser_service.dart';
import '../../services/history_service.dart';
import '../../services/organize/apply_controller.dart';
import '../../services/task_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/path_tree.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';
import 'organize_preview_dialog.dart';

/// 右侧面板（3.1）：AI 的思考过程、建议目标树、预览入口与用量条。
///
/// 宽 352 由外壳决定（2.6），这里只管内容：内距 18、纵向 gap 14。
class AiAssistantPanel extends StatelessWidget {
  const AiAssistantPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final ai = context.watch<AiService>();
    final plan = ai.currentPlan;

    return AppGlassPane(
      border: Border(left: BorderSide(color: t.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(analyzing: ai.isAnalyzing, hasPlan: plan != null),
          Expanded(
            child: (plan == null && !ai.isAnalyzing)
                ? _Idle(configured: ai.isConfigured)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              // 「预览」而不是「应用」：这一步只打开确认对话框，方案在那里被
              // 审阅、修改，然后才落盘。整条流水线里它是唯一的 dry-run 闸门。
              child: AppButton.primary(
                label: l10n.previewOrganize,
                icon: Icons.visibility_outlined,
                height: 34,
                expand: true,
                onPressed: () => _confirmApply(context, ai),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, AppSpacing.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md12,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: t.isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : AppPalette.ink.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(AppRadii.field),
              ),
              child: Row(
                children: [
                  Text(
                    l10n.usage,
                    style: AppTypeScale.caption.copyWith(color: t.textMuted),
                  ),
                  const Spacer(),
                  Text(
                    l10n.tokensLabel(ai.lastTokens),
                    style: context.tokens.monoSmall.copyWith(color: t.textBody),
                  ),
                ],
              ),
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

    // Only an applied preview is remembered: cancelling means the corrections
    // were never the user's decision. Best effort — it must not hold up the
    // apply they just confirmed.
    ai.rememberEdits(plan, baseDir).ignore();

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
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                result.hasFailures
                    ? l10n.applyPartial(result.failed, result.succeeded)
                    : l10n.applyDone(result.succeeded),
              ),
            ),
          );
        }
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
}

class _Header extends StatelessWidget {
  final bool analyzing;
  final bool hasPlan;
  const _Header({required this.analyzing, required this.hasPlan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Container(
            width: AppSizes.logo,
            height: AppSizes.logo,
            decoration: BoxDecoration(
              gradient: t.brandGradient,
              borderRadius: BorderRadius.circular(AppRadii.button),
              boxShadow: t.reduceEffects
                  ? null
                  : [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 13,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiAssistant,
                  style: AppTypeScale.bodyStrong.copyWith(color: t.textTitle),
                ),
                Text(
                  analyzing
                      ? l10n.analyzingSelected
                      : (hasPlan ? l10n.analysisComplete : l10n.aiPanelIdle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tokens.monoTiny.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「思考过程」卡：accent 8% + 描边 accent 18%（3.1）。
class _ReasoningCard extends StatelessWidget {
  final OrganizePlan? plan;
  final bool analyzing;
  const _ReasoningCard({required this.plan, required this.analyzing});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final steps = plan?.reasoning ?? const [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: t.accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reasoning,
            style: AppTypeScale.groupLabel.copyWith(
              letterSpacing: 0.06 * 10,
              color: t.accentText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (analyzing && steps.isEmpty)
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  l10n.analyzing,
                  style: AppTypeScale.caption.copyWith(color: t.textSecondary),
                ),
              ],
            )
          else
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 已完成的步骤是 ✓，还在跑的最后一条是 ● —— 设计稿用两个
                    // 不同的字形而不是同一个对勾的两种深浅，因为「做完了」和
                    // 「正在做」是两件事，不是一件事的两种强度。
                    Text(
                      analyzing && i == steps.length - 1 ? '●' : '✓',
                      style: TextStyle(
                        fontSize: AppTypeScale.sizeMono,
                        height: 1.55,
                        color: analyzing && i == steps.length - 1
                            ? t.accentText
                            : t.successText,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: AppTypeScale.caption.copyWith(
                          height: 1.55,
                          color: analyzing && i == steps.length - 1
                              ? t.textSecondary
                              : t.textBody,
                        ),
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

/// 「建议目标」卡：mono 树，逐层缩进 10，叶子取强调色（3.1）。
class _TargetStructureCard extends StatelessWidget {
  final OrganizePlan plan;
  const _TargetStructureCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final lines = buildPathTree(plan.actions.map((a) => a.target).toList());

    return AppCard(
      radius: AppRadii.panel,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.targetStructure,
            style: AppTypeScale.groupLabel.copyWith(
              letterSpacing: 0.06 * 10,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final line in lines)
            Padding(
              padding: EdgeInsets.only(left: line.depth * AppSpacing.md),
              child: Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tokens.monoSmall.copyWith(
                  height: 1.7,
                  color: line.isDir
                      ? t.textSecondary
                      : (t.isDark ? AppPalette.accentOnDarkSoft : t.accentInk),
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
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 40,
              color: t.textMuted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(
              configured ? l10n.aiPanelIdle : l10n.aiNotConfigured,
              textAlign: TextAlign.center,
              style: AppTypeScale.caption.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
