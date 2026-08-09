import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/scrape/image_downloader.dart';
import '../../services/scrape/scrape_service.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_dialog.dart';

/// What the user confirmed for a folder-wide refresh.
class BatchScrapeDecision {
  final List<RescrapeTarget> targets;
  final ImageSelection images;
  final bool backup;

  const BatchScrapeDecision({
    required this.targets,
    required this.images,
    required this.backup,
  });
}

/// The gate for a batch refresh.
///
/// Single-title scraping gets a field-level diff; a batch cannot — three
/// hundred dialogs is a fatigue test, not review. So this dialog states the
/// merge policy plainly, lists exactly what will be touched, and lets the user
/// deselect anything they do not want. Cancelling writes nothing.
Future<BatchScrapeDecision?> showBatchScrapeDialog(
  BuildContext context, {
  required List<RescrapeTarget> targets,
}) => showDialog<BatchScrapeDecision>(
  context: context,
  builder: (_) => _BatchScrapeDialog(targets: targets),
);

class _BatchScrapeDialog extends StatefulWidget {
  final List<RescrapeTarget> targets;
  const _BatchScrapeDialog({required this.targets});

  @override
  State<_BatchScrapeDialog> createState() => _BatchScrapeDialogState();
}

class _BatchScrapeDialogState extends State<_BatchScrapeDialog> {
  late final Set<String> _selected = {for (final t in widget.targets) _key(t)};
  bool _artwork = false;
  bool _backup = true;

  static String _key(RescrapeTarget t) => '${t.targetDir}/${t.nfoFileName}';

  List<RescrapeTarget> get _chosen =>
      widget.targets.where((t) => _selected.contains(_key(t))).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final empty = widget.targets.isEmpty;

    return GlassAlertDialog(
      maxWidth: 668,
      icon: Icon(Icons.refresh_rounded, color: scheme.primary),
      title: Text(l10n.batchScrapeTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: empty
            ? Text(
                l10n.batchScrapeEmpty,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.batchScrapeFound(widget.targets.length),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: glass.panelFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: glass.panelStroke),
                    ),
                    child: Text(
                      l10n.batchScrapePolicy,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.targets.length,
                      itemBuilder: (_, i) {
                        final t = widget.targets[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(_key(t)),
                          onChanged: (v) => setState(() {
                            if (v ?? false) {
                              _selected.add(_key(t));
                            } else {
                              _selected.remove(_key(t));
                            }
                          }),
                          title: Text(
                            t.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            t.sourceUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 18),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _artwork,
                    onChanged: (v) => setState(() => _artwork = v ?? false),
                    title: Text(
                      l10n.batchScrapeArtwork,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      l10n.batchScrapeArtworkHint,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _backup,
                    onChanged: (v) => setState(() => _backup = v ?? true),
                    title: Text(
                      l10n.scrapeWriteBackup,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            empty
                ? MaterialLocalizations.of(context).closeButtonLabel
                : l10n.cancel,
          ),
        ),
        if (!empty)
          FilledButton.icon(
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    BatchScrapeDecision(
                      targets: _chosen,
                      images: _artwork
                          ? ImageSelection.posterOnly
                          : ImageSelection.none,
                      backup: _backup,
                    ),
                  ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.batchScrapeStart(_chosen.length)),
          ),
      ],
    );
  }
}
