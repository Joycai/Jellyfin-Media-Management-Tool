import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/font_service.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/format.dart';
import '../glass/glass_dialog.dart';

// ── Font picker ─────────────────────────────────────────────────────────────

class FontOption extends StatelessWidget {
  final AppFontChoice choice;
  const FontOption({super.key, required this.choice});

  String _label(AppLocalizations l10n) => switch (choice) {
    AppFontChoice.system => l10n.fontSystem,
    AppFontChoice.harmony => 'HarmonyOS Sans',
    AppFontChoice.misans => 'MiSans',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final fonts = context.watch<FontService>();
    final scheme = Theme.of(context).colorScheme;
    final selected = settings.fontChoice == choice.id;
    final downloaded = fonts.isDownloadedSync(choice);

    final String? status = choice == AppFontChoice.system
        ? null
        : (downloaded
              ? l10n.fontStatusDownloaded
              : l10n.fontStatusNotDownloaded);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: () => _select(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.onSurfaceVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                // min + Row's default center alignment keeps the text block
                // vertically centered when the card is stretched taller than
                // its content (see IntrinsicHeight in the appearance section).
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypeScale.sizeBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: AppTypeScale.sizeCaption,
                          color: downloaded
                              ? AppPalette.success
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _select(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    final fonts = context.read<FontService>();

    if (choice == AppFontChoice.system || fonts.isLoaded(choice)) {
      await settings.setFontChoice(choice.id);
      return;
    }
    // Downloaded on a previous run but not registered yet (it wasn't the
    // active font at startup) — register and switch, no download needed.
    if (fonts.isDownloadedSync(choice)) {
      await fonts.loadIfDownloaded(choice);
      await settings.setFontChoice(choice.id);
      return;
    }

    final name = _label(l10n);
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        title: Text(l10n.fontDownloadTitle),
        content: Text(l10n.fontDownloadConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.downloadAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await showGlassDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FontDownloadDialog(choice: choice, name: name),
    );
    if (ok == true) {
      await settings.setFontChoice(choice.id);
    }
  }
}

/// Modal progress dialog that runs the download and pops `true` on success,
/// `false` on failure (after surfacing the error via a snackbar).
class _FontDownloadDialog extends StatefulWidget {
  final AppFontChoice choice;
  final String name;
  const _FontDownloadDialog({required this.choice, required this.name});

  @override
  State<_FontDownloadDialog> createState() => _FontDownloadDialogState();
}

class _FontDownloadDialogState extends State<_FontDownloadDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final fonts = context.read<FontService>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    try {
      await fonts.downloadAndLoad(widget.choice);
      if (mounted) navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.fontDownloadFailed(e.toString()))),
      );
      if (mounted) navigator.pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fonts = context.watch<FontService>();
    final scheme = Theme.of(context).colorScheme;
    final received = fonts.receivedBytes;
    final total = fonts.totalBytes;

    return GlassAlertDialog(
      title: Text(l10n.fontDownloading(widget.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: LinearProgressIndicator(
              value: (fonts.progress ?? 0) > 0 ? fonts.progress : null,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            total > 0
                ? '${formatBytes(received)} / ${formatBytes(total)}'
                : formatBytes(received),
            style: TextStyle(
              fontSize: AppTypeScale.sizeControl,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
