import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../models/organize_plan.dart';
import '../../services/file_label_service.dart';
import '../../services/path_safety.dart';
import '../../services/rename_service.dart';
import '../dialogs/part_dialog.dart';
import '../dialogs/subtitle_dialog.dart';
import '../dialogs/tv_show_dialog.dart';

/// Corrects one planned action's target path before anything is written.
///
/// Returns the new folder-relative target, or null when the user cancels.
/// Nothing here touches the filesystem: the naming-rule shortcuts rewrite only
/// the last path segment through [RenameService.buildName], and the actual move
/// still happens later in `ApplyController`.
class EditActionDialog extends StatefulWidget {
  final OrganizeAction action;

  /// Folder being organized — targets are validated to stay inside it.
  final String baseDir;

  /// Video targets elsewhere in the plan, offered as the anchor filename for
  /// the Jellyfin subtitle rule.
  final List<String> videoTargets;

  const EditActionDialog({
    super.key,
    required this.action,
    required this.baseDir,
    required this.videoTargets,
  });

  static Future<String?> show(
    BuildContext context, {
    required OrganizeAction action,
    required String baseDir,
    required List<String> videoTargets,
  }) => showDialog<String>(
    context: context,
    builder: (_) => EditActionDialog(
      action: action,
      baseDir: baseDir,
      videoTargets: videoTargets,
    ),
  );

  @override
  State<EditActionDialog> createState() => _EditActionDialogState();
}

class _EditActionDialogState extends State<EditActionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.action.target,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isSubtitle =>
      FileLabelService.getLabel(p.extension(widget.action.target)) ==
      'Subtitle';

  /// Null when [raw] is a usable relative target, otherwise the reason it is
  /// not. Mirrors the containment check `applyOrganizeAction` enforces, so the
  /// user finds out here rather than as a failed row mid-apply.
  String? _validate(String raw, AppLocalizations l10n) {
    final value = raw.trim();
    if (value.isEmpty || p.isAbsolute(value)) return l10n.targetPathInvalid;
    final normalized = p.normalize(value);
    if (p.basename(normalized).isEmpty) return l10n.targetPathInvalid;
    if (!PathSafety.isWithin(
      widget.baseDir,
      p.join(widget.baseDir, normalized),
    )) {
      return l10n.targetPathInvalid;
    }
    return null;
  }

  void _submit(AppLocalizations l10n) {
    final error = _validate(_controller.text, l10n);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, p.normalize(_controller.text.trim()));
  }

  /// Rewrites just the filename of the current target using [rule], keeping the
  /// directory part the user sees in the field.
  Future<void> _applyRule(RenameRule rule) async {
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
      // SubtitleDialog only reads the basename off these, so synthetic File
      // handles over the planned targets are enough — none of them exist yet.
      final r = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SubtitleDialog(
          videoFiles: widget.videoTargets.map(File.new).toList(),
          initialLang: 'zh-Hans',
          initialDefault: false,
        ),
      );
      if (r == null) return;
      extra = r['result'] as String;
    }

    final current = p.normalize(_controller.text.trim());
    final name = RenameService.buildName(
      RenameService.baseNameForTarget(current),
      p.extension(current),
      rule,
      extra: extra,
    );
    final dir = p.dirname(current);
    if (!mounted) return;
    setState(() {
      _controller.text = (dir == '.' || dir.isEmpty) ? name : p.join(dir, name);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n.editTargetTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.action.source,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: l10n.targetPathLabel,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(l10n),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.namingRules,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ruleChip(l10n.matchFolderName, RenameRule.matchFolder),
                _ruleChip(l10n.renameToFeaturette, RenameRule.featurette),
                _ruleChip(l10n.renameToInterview, RenameRule.interview),
                _ruleChip(l10n.renameToPart, RenameRule.part),
                _ruleChip(l10n.renameToTVShow, RenameRule.tvShow),
                if (_isSubtitle && widget.videoTargets.isNotEmpty)
                  _ruleChip(l10n.jellyfinSubtitle, RenameRule.subtitle),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: () => _submit(l10n), child: Text(l10n.save)),
      ],
    );
  }

  Widget _ruleChip(String label, RenameRule rule) =>
      ActionChip(label: Text(label), onPressed: () => _applyRule(rule));
}
