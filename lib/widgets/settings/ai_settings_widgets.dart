/// Building blocks shared by the AI access pages: labelled fields, the
/// sampling card, protocol chips, vendor badges.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/platform_profiles.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';

/// Protocol family names. Wire-protocol names, the same in every language,
/// so they are not in the ARB files.
String protocolName(AiProviderType protocol) => switch (protocol) {
  AiProviderType.openAi => 'Chat Completions',
  AiProviderType.openAiResponses => 'Responses',
  AiProviderType.googleGenAi => 'Gemini',
  AiProviderType.anthropic => 'Anthropic',
};

/// The short form the overview's route chips use.
String protocolShortName(AiProviderType protocol) => switch (protocol) {
  AiProviderType.openAi => 'Chat',
  AiProviderType.openAiResponses => 'Resp',
  AiProviderType.googleGenAi => 'Gemini',
  AiProviderType.anthropic => 'Anth',
};

/// Whether this build has an adapter for [protocol]. A route on one it does
/// not would be drawn, disabled and labelled, never offered. Every protocol
/// family has one now; the switch stays so the next family can arrive as
/// data first and be switched on with its adapter.
bool protocolInBuild(AiProviderType protocol) => switch (protocol) {
  AiProviderType.openAi ||
  AiProviderType.googleGenAi ||
  AiProviderType.anthropic ||
  AiProviderType.openAiResponses => true,
};

/// A platform's name in the UI language. Product names stay as they are.
String platformName(AppLocalizations l10n, PlatformProfile platform) =>
    switch (platform.id) {
      'relay' => l10n.aiPlatformRelay,
      'custom' => l10n.aiPlatformCustom,
      'dashscope' => l10n.aiPlatformDashScope,
      'zhipu' => l10n.aiPlatformZhipu,
      'volcengine' => l10n.aiPlatformVolcengine,
      _ => platform.name,
    };

/// A platform's badge colours and glyph. Vendor marks, not theme colours:
/// following the accent would make a user's own services unrecognisable.
({Color color, String glyph}) platformBadge(PlatformProfile platform) =>
    switch (platform.id) {
      'openai' => (color: AppPalette.vendorOpenAi.first, glyph: '◆'),
      'google' => (color: AppPalette.vendorGoogle.first, glyph: 'G'),
      _ when platform.kind == PlatformKind.local => (
        color: AppPalette.vendorLocal.first,
        glyph: platform.name.characters.first,
      ),
      _ when platform.kind == PlatformKind.custom => (
        color: AppPalette.typeNeutral,
        glyph: '·',
      ),
      _ => (color: AppPalette.accent, glyph: platform.name.characters.first),
    };

/// A rounded, gradient vendor badge.
class AiBadge extends StatelessWidget {
  final PlatformProfile platform;

  /// 6.1's service cards draw 40; the page headers 44.
  final double size;

  const AiBadge({super.key, required this.platform, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final badge = platformBadge(platform);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            badge.color,
            Color.lerp(badge.color, AppPalette.darkBase, 0.25)!,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.icon),
      ),
      alignment: Alignment.center,
      child: Text(
        badge.glyph,
        style: AppTypeScale.bodyStrong.copyWith(
          color: AppPalette.onTerminal,
          fontSize: size >= 40
              ? AppTypeScale.sizeSubheading
              : AppTypeScale.sizeBody,
        ),
      ),
    );
  }
}

/// A protocol chip: filled for the route in use, outlined for an enabled
/// one, dashed-looking (muted) for one the platform offers but that is off.
enum ProtocolChipState { current, enabled, offered }

class ProtocolChip extends StatelessWidget {
  final AiProviderType protocol;
  final ProtocolChipState state;
  final bool short;

  const ProtocolChip({
    super.key,
    required this.protocol,
    this.state = ProtocolChipState.enabled,
    this.short = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = short ? protocolShortName(protocol) : protocolName(protocol);
    final (fill, border, ink) = switch (state) {
      ProtocolChipState.current => (t.accent, t.accent, t.badgeText),
      ProtocolChipState.enabled => (
        t.accent.withValues(alpha: 0.10),
        t.accent.withValues(alpha: 0.45),
        t.accent,
      ),
      ProtocolChipState.offered => (
        t.accent.withValues(alpha: 0),
        t.stroke,
        t.textMuted,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        label,
        style: t.monoTiny.copyWith(color: ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A small tinted status label (tools, image, video).
class AiStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const AiStatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs / 2,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadii.chip),
    ),
    child: Text(
      label,
      style: AppTypeScale.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class AiFieldLabel extends StatelessWidget {
  final String text;
  const AiFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypeScale.controlStrong.copyWith(color: context.tokens.textMuted),
  );
}

/// A labelled, card-styled input.
class AiField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool mono;
  final bool obscure;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;

  /// Placeholder shown while the field is empty.
  final String? hint;

  /// Accept only digits, for token counts.
  final bool digitsOnly;

  /// Accept a non-negative decimal, for sampling values.
  final bool decimal;

  /// The value range, right-aligned on the label row (6.1's sampling grid).
  final String? range;

  /// A value this field cannot take, drawn struck through with the reason.
  final bool refused;

  const AiField({
    super.key,
    required this.label,
    required this.controller,
    this.mono = false,
    this.obscure = false,
    this.trailing,
    this.onChanged,
    this.hint,
    this.digitsOnly = false,
    this.decimal = false,
    this.range,
    this.refused = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md12,
        AppSpacing.lg,
        AppSpacing.md12,
      ),
      decoration: BoxDecoration(
        color: t.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: t.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypeScale.controlStrong.copyWith(
                    color: t.textMuted,
                    decoration: refused ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (range != null)
                Text(range!, style: t.monoTiny.copyWith(color: t.textMuted)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  onChanged: onChanged,
                  keyboardType: digitsOnly
                      ? TextInputType.number
                      : decimal
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : null,
                  inputFormatters: [
                    if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
                    // One optional decimal point, digits either side.
                    if (decimal)
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  style: (mono ? t.monoBody : AppTypeScale.title).copyWith(
                    color: t.textBody,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText: hint,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A card with a title, an optional note beside it, and a body.
class AiCard extends StatelessWidget {
  final String? title;
  final String? note;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// The card takes all the height it is given and [child] fills what is
  /// left under the title — for a list or a preview in a stretched column.
  /// Only for a card with bounded height; in a scroll view leave it false.
  final bool fill;

  const AiCard({
    super.key,
    this.title,
    this.note,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: t.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title!,
                  style: AppTypeScale.bodyStrong.copyWith(color: t.textTitle),
                ),
                if (note != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypeScale.caption.copyWith(color: t.textMuted),
                    ),
                  ),
                ] else
                  const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md12),
          ],
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

/// What the last connection test found the server reporting, with a way to
/// adopt it. Only the user can say whether a model's maximum is really what
/// they loaded, so nothing is filled in without this click.
class AiDetectedLimits extends StatelessWidget {
  final ModelLimits limits;
  final VoidCallback onUse;
  const AiDetectedLimits({
    super.key,
    required this.limits,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final source = limits.source ?? '';
    final window = limits.contextWindow;
    final found = !limits.isEmpty;
    final parts = <String>[
      if (window != null)
        limits.isModelMaximum
            ? l10n.detectedModelMaximum(source, window)
            : l10n.detectedContextWindow(source, window),
      if (limits.maxOutputTokens case final output?)
        l10n.detectedMaxOutput(output),
    ];
    return Row(
      children: [
        Icon(
          found ? Icons.radar_rounded : Icons.help_outline_rounded,
          size: AppSizes.menuIconColumn - 2,
          color: found ? t.accent : t.textMuted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            found ? parts.join(' · ') : l10n.limitsNotDetected,
            style: AppTypeScale.control.copyWith(color: t.textBody),
          ),
        ),
        if (found)
          AppButton.ghost(
            label: l10n.useDetectedValue,
            height: AppSizes.controlSm,
            onPressed: onUse,
          ),
      ],
    );
  }
}

enum SamplingField {
  temperature,
  topP,
  topK,
  minP,
  presencePenalty,
  repeatPenalty,
}

/// The sampling fields and the reasoning switch for one model on one route:
/// which preset applies, one field per parameter with the preset's value as
/// its placeholder, and what the last test showed about reasoning.
///
/// Every field is optional on purpose. A blank one follows the preset, so the
/// recommended values keep working after a model is swapped for another
/// family; typing a value is an explicit override.
class AiSamplingSection extends StatelessWidget {
  final SamplingPreset? preset;
  final Map<SamplingField, TextEditingController> controllers;
  final bool thinking;

  /// Whether the platform has its own reasoning switch, which works for any
  /// model on it — not only the families a preset knows are hybrid.
  final bool platformSwitch;

  /// What the last test on this route showed; null when none ran.
  final bool? lastReasoned;
  final ServerKind? serverKind;

  /// Wire names this route refused; their fields are drawn struck through.
  final Set<String> refused;
  final VoidCallback onChanged;
  final ValueChanged<bool> onThinkingChanged;
  final VoidCallback onReset;

  const AiSamplingSection({
    super.key,
    required this.preset,
    required this.controllers,
    required this.thinking,
    required this.platformSwitch,
    required this.lastReasoned,
    required this.serverKind,
    required this.refused,
    required this.onChanged,
    required this.onThinkingChanged,
    required this.onReset,
  });

  static const _rows = [
    (SamplingField.temperature, SamplingField.topP),
    (SamplingField.topK, SamplingField.minP),
    (SamplingField.presencePenalty, SamplingField.repeatPenalty),
  ];

  /// What each field is called on the Chat Completions wire.
  static const wireNames = {
    SamplingField.temperature: 'temperature',
    SamplingField.topP: 'top_p',
    SamplingField.topK: 'top_k',
    SamplingField.minP: 'min_p',
    SamplingField.presencePenalty: 'presence_penalty',
    SamplingField.repeatPenalty: 'repeat_penalty',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final preset = this.preset;
    // Mirrors what the provider sends: a known family decides whether its
    // reasoning can be switched at all; a model no preset knows can be
    // switched only where the platform has a switch.
    final switchable = preset != null
        ? preset.thinkingIsOptional
        : platformSwitch;
    final reasons = preset?.reasons(requested: thinking) ?? thinking;
    final values = preset?.valuesFor(thinking: reasons);
    final status = _thinkingStatus(l10n, reasons, switchable);
    final note = AppTypeScale.caption.copyWith(color: t.textMuted);

    String label(SamplingField field) => switch (field) {
      SamplingField.temperature => l10n.temperature,
      SamplingField.topP => l10n.samplingTopP,
      SamplingField.topK => l10n.samplingTopK,
      SamplingField.minP => l10n.samplingMinP,
      SamplingField.presencePenalty => l10n.samplingPresencePenalty,
      SamplingField.repeatPenalty => l10n.samplingRepeatPenalty,
    };

    // What a blank field sends: the preset's value for the mode reasoning
    // will run in, or — outside every preset — the old fixed temperature.
    String placeholder(SamplingField field) {
      final value = switch (field) {
        SamplingField.temperature =>
          values?.temperature ??
              (preset == null ? ResolvedSampling.legacyTemperature : null),
        SamplingField.topP => values?.topP,
        SamplingField.topK => values?.topK,
        SamplingField.minP => values?.minP,
        SamplingField.presencePenalty => values?.presencePenalty,
        SamplingField.repeatPenalty => values?.repeatPenalty,
      };
      return value == null ? l10n.samplingDefault : '$value';
    }

    // 6.1's six ranges. Conventions of the models, the same in every
    // language, so not in the ARB files.
    const ranges = {
      SamplingField.temperature: '0 – 2',
      SamplingField.topP: '0 – 1',
      SamplingField.topK: '1 – 200',
      SamplingField.minP: '0 – 1',
      SamplingField.presencePenalty: '-2 – 2',
      SamplingField.repeatPenalty: '1 – 2',
    };

    Widget field(SamplingField which) => AiField(
      label: label(which),
      controller: controllers[which]!,
      mono: true,
      hint: placeholder(which),
      range: ranges[which],
      digitsOnly: which == SamplingField.topK,
      decimal: which != SamplingField.topK,
      refused: refused.contains(wireNames[which]),
      onChanged: (_) => onChanged(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.thinkingMode,
                    style: AppTypeScale.bodyStrong.copyWith(color: t.textTitle),
                  ),
                  const SizedBox(height: AppSpacing.xxs / 2),
                  Text(l10n.thinkingModeHint, style: note),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md12),
            // 6.1's 38 x 22 switch, not Material's Switch.
            AppToggle(
              value: reasons,
              width: 38,
              height: 22,
              // Only reasoning that really can be switched gets a live
              // control; anything else would be a switch that does nothing.
              onChanged: switchable ? onThinkingChanged : null,
            ),
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            status.text,
            style: note.copyWith(color: status.warning ? t.danger : null),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AiFieldLabel(l10n.samplingTitle),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                preset == null
                    ? l10n.samplingNoPreset
                    : l10n.samplingPresetMatched(preset.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypeScale.control.copyWith(color: t.textMuted),
              ),
            ),
            if (preset != null)
              AppButton.ghost(
                label: l10n.samplingPresetSource,
                height: AppSizes.controlSm,
                onPressed: () => launchUrl(
                  Uri.parse(preset.source),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            AppButton.ghost(
              label: l10n.samplingReset,
              height: AppSizes.controlSm,
              onPressed: onReset,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final (left, right) in _rows) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: field(left)),
              const SizedBox(width: AppSpacing.md12),
              Expanded(child: field(right)),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
        ],
        Text(l10n.samplingNote, style: note),
        if (refused.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.aiRefusedFields((refused.toList()..sort()).join(', ')),
            style: note,
          ),
        ],
        if (preset?.needsSystemPrompt ?? false) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.presetNeedsSystemPrompt, style: note),
        ],
        if (serverKind == ServerKind.ollama) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.ollamaIgnoresSampling, style: note),
        ],
      ],
    );
  }

  /// A line under the switch: what the family allows, or — when reasoning
  /// can be switched off — whether the last test showed it actually was.
  /// That second case is the one worth a line, because servers ignore the
  /// fields that turn it off without saying so.
  ({String text, bool warning})? _thinkingStatus(
    AppLocalizations l10n,
    bool reasons,
    bool switchable,
  ) {
    switch (preset?.thinkingControl) {
      case ThinkingControl.alwaysOn:
        return (text: l10n.thinkingAlwaysOn, warning: false);
      case ThinkingControl.effortOnly:
        return (text: l10n.thinkingEffortOnly, warning: false);
      default:
        break;
    }
    final reasoned = lastReasoned;
    if (reasoned == null || reasons || !switchable) return null;
    return reasoned
        ? (text: l10n.thinkingStillOn, warning: true)
        : (text: l10n.thinkingVerifiedOff, warning: false);
  }
}

/// A rounded rectangle with a dashed border (for "add" affordances).
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRectPainter(
      color: context.tokens.strokeStrong,
      radius: AppRadii.panel,
    ),
    child: child,
  );
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}
