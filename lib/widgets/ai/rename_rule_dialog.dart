/// The naming-rule editor — UI only, for now.
///
/// Reached from the organize preview's "Adjust rules" button. It shows the
/// built-in Jellyfin movie convention as template chips with a live-preview
/// column, exactly per the design mockup, but nothing is editable yet: the
/// templates are the hardcoded convention `AiPrompt` actually uses, Reset is
/// disabled, and Save simply closes. A banner says so — a screen that looks
/// configurable but silently ignores input would be worse than a placeholder
/// that admits it. Wiring the templates into the prompt is a separate feature.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_dialog.dart';

class RenameRuleDialog extends StatefulWidget {
  const RenameRuleDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const RenameRuleDialog(),
  );

  @override
  State<RenameRuleDialog> createState() => _RenameRuleDialogState();
}

class _RenameRuleDialogState extends State<RenameRuleDialog> {
  /// Visual only — the AI-fill behaviour is not configurable yet.
  bool _aiFill = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 640),
        child: GlassDialogSurface(
          child: Column(
            children: [
              _header(l10n, scheme),
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _templates(l10n, scheme)),
                    VerticalDivider(
                      width: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    SizedBox(width: 340, child: _preview(l10n, scheme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 16, 16, 14),
    child: Row(
      children: [
        Text(
          l10n.ruleEditorTitle,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.secondary.withValues(alpha: 0.3)),
          ),
          child: Text(
            l10n.ruleEditorRecommended,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.secondary,
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton(
          // Nothing to reset to until rules are actually editable.
          onPressed: null,
          child: Text(l10n.ruleEditorReset),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).saveButtonLabel),
        ),
      ],
    ),
  );

  // ── Left: templates ───────────────────────────────────────────────────────

  Widget _templates(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(l10n.ruleEditorFolderTemplate, scheme),
          const SizedBox(height: 8),
          _templateBox(glass, [
            _mono('Movies/', scheme),
            _VarChip(name: '{title}', color: scheme.primary),
            _VarChip(name: '({year})', color: scheme.tertiary),
            _mono('/', scheme),
          ]),
          const SizedBox(height: 18),
          _label(l10n.ruleEditorFileTemplate, scheme),
          const SizedBox(height: 8),
          _templateBox(glass, [
            _VarChip(name: '{title}', color: scheme.primary),
            _VarChip(name: '({year})', color: scheme.tertiary),
            _mono('.', scheme),
            _VarChip(name: '{ext}', color: scheme.secondary),
          ]),
          const SizedBox(height: 18),
          _label(l10n.ruleEditorVariables, scheme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _VarChip(name: '{title}', color: scheme.primary),
              _VarChip(name: '{year}', color: scheme.tertiary),
              _VarChip(name: '{ext}', color: scheme.secondary),
              for (final v in const [
                '{tmdb_id}',
                '{quality}',
                '{lang}',
                '{edition}',
              ])
                _VarChip(name: v, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 22),
          // The honest banner: this screen previews the convention, it does
          // not change it yet.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFE0852C).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Color(0xFFE0852C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.ruleEditorComingSoon,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: glass.panelFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glass.panelStroke),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: scheme.tertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.ruleEditorAiFill,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.ruleEditorAiFillHint,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Switch(
                  value: _aiFill,
                  onChanged: (v) => setState(() => _aiFill = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateBox(GlassTheme glass, List<Widget> parts) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: glass.panelFill,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: glass.panelStroke),
    ),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    ),
  );

  // ── Right: live preview ───────────────────────────────────────────────────

  Widget _preview(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(l10n.ruleEditorPreview, scheme),
          const SizedBox(height: 10),
          _previewCard(
            glass,
            scheme,
            input: 'Dune.Part.Two.2024.2160p.WEB-DL.x265.HDR.mkv',
            outputLabel: l10n.ruleEditorOutput,
            outputColor: scheme.onSurfaceVariant,
            lines: const [
              ('Movies/', 0),
              ('Dune: Part Two (2024)/', 1),
              ('Dune Part Two (2024).mkv', 2),
            ],
          ),
          const SizedBox(height: 12),
          _previewCard(
            glass,
            scheme,
            input: 'interstellar_imax_v2.mkv',
            outputLabel: l10n.ruleEditorOutputAi,
            outputColor: scheme.tertiary,
            lines: const [
              ('Movies/', 0),
              ('Interstellar (2014)/', 1),
              ('Interstellar (2014).mkv', 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewCard(
    GlassTheme glass,
    ColorScheme scheme, {
    required String input,
    required String outputLabel,
    required Color outputColor,
    required List<(String, int)> lines,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: glass.panelFill,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: glass.panelStroke),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(AppLocalizations.of(context)!.ruleEditorInput, scheme),
        const SizedBox(height: 4),
        Text(
          input,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        Text(
          outputLabel,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: outputColor,
          ),
        ),
        const SizedBox(height: 4),
        for (final (text, depth) in lines)
          Padding(
            padding: EdgeInsets.only(left: depth * 14.0, top: 2),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: depth == 1 ? FontWeight.w700 : FontWeight.w400,
                color: switch (depth) {
                  0 => scheme.onSurfaceVariant,
                  1 => scheme.primary,
                  _ => scheme.secondary,
                },
              ),
            ),
          ),
      ],
    ),
  );

  Widget _label(String text, ColorScheme scheme) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: scheme.onSurfaceVariant,
    ),
  );

  Widget _mono(String text, ColorScheme scheme) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontFamily: 'monospace',
      color: scheme.onSurfaceVariant,
    ),
  );
}

/// One template variable, tinted so the same variable reads as the same thing
/// wherever it appears — template, palette, or (one day) a drag source.
class _VarChip extends StatelessWidget {
  final String name;
  final Color color;

  const _VarChip({required this.name, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      name,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}
