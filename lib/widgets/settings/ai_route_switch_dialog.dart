import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/platform_profiles.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';
import 'ai_settings_widgets.dart';

/// Shows, parameter by parameter, what moving [model] to [to] changes, and
/// resolves to true when the user confirms (RouteSwitch artboard).
///
/// The point of the table is the right-hand column: values the new route had
/// before come back, and everything else reads "not set · not sent" rather
/// than being quietly copied from a protocol where it meant something else.
Future<bool> confirmRouteSwitch(
  BuildContext context, {
  required AiChannel channel,
  required AiModelEntry model,
  required AiProviderType to,
}) async =>
    await showGlassDialog<bool>(
      context: context,
      builder: (_) => RouteSwitchDialog(channel: channel, model: model, to: to),
    ) ??
    false;

class RouteSwitchDialog extends StatelessWidget {
  final AiChannel channel;
  final AiModelEntry model;
  final AiProviderType to;

  const RouteSwitchDialog({
    super.key,
    required this.channel,
    required this.model,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final from = channel.configFor(model).provider;
    final now = model.params[from] ?? RouteParams.empty;
    final after = model.params[to];
    final nowConfig = channel.configFor(model);
    final afterConfig = channel.configFor(model.switchedTo(to));
    final notSet = l10n.aiNotSetNotSent;

    // The platform field is named only while it still works both ways:
    // one this route refused is not what on and off send.
    String thinking(RouteParams p, AiConfig config) {
      final (:route, :field) = PlatformProfiles.reasoningRouteFor(
        config,
        AiService.providerFor(config).learned,
      );
      final state = p.thinkingEnabled ? l10n.aiOn : l10n.aiOff;
      return route == ReasoningRoute.platformField ? '$state · $field' : state;
    }

    String sampling(RouteParams p) {
      final parts = [
        if (p.temperature != null) 'temperature ${p.temperature}',
        if (p.topP != null) 'top_p ${p.topP}',
        if (p.topK != null) 'top_k ${p.topK}',
        if (p.minP != null) 'min_p ${p.minP}',
        if (p.presencePenalty != null) 'presence_penalty ${p.presencePenalty}',
        if (p.repeatPenalty != null) 'repeat_penalty ${p.repeatPenalty}',
      ];
      return parts.isEmpty ? l10n.samplingDefault : parts.join(' · ');
    }

    String tools(AiConfig config) => switch (config.supportsTools) {
      true => l10n.aiToolsMeasured,
      false => l10n.aiToolsMeasuredNo,
      null => l10n.aiToolsProbeAfter,
    };

    final rows = <(String, String, String?, bool)>[
      (
        l10n.aiParamThinking,
        thinking(now, nowConfig),
        after == null ? null : thinking(after, afterConfig),
        false,
      ),
      (
        l10n.aiParamMaxOutput,
        now.maxOutputTokens?.toString() ?? l10n.samplingDefault,
        after == null
            ? null
            : (after.maxOutputTokens?.toString() ?? l10n.samplingDefault),
        false,
      ),
      (
        l10n.aiParamSampling,
        sampling(now),
        after == null ? null : sampling(after),
        false,
      ),
      (
        l10n.aiParamTools,
        tools(nowConfig),
        tools(afterConfig),
        afterConfig.supportsTools == null,
      ),
      (
        l10n.aiParamImage,
        model.imageInput ? l10n.aiCapAllowed : l10n.aiCapNotAllowed,
        model.imageInput ? l10n.aiCapAllowed : l10n.aiCapNotAllowed,
        false,
      ),
    ];

    TextStyle cell = t.monoSmall.copyWith(color: t.textBody);

    return GlassAlertDialog(
      // RouteSwitch artboard: a 720-wide comparison table.
      maxWidth: 720,
      title: Text(
        l10n.aiSwitchTitle(
          model.upstream,
          protocolName(from),
          protocolName(to),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.aiSwitchBody),
          const SizedBox(height: AppSpacing.md12),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(horizontalInside: BorderSide(color: t.stroke)),
            children: [
              TableRow(
                children: [
                  for (final header in [
                    l10n.aiSwitchParam,
                    l10n.aiSwitchNow(protocolName(from)),
                    l10n.aiSwitchAfter(protocolName(to)),
                  ])
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        header,
                        style: AppTypeScale.columnHeader.copyWith(
                          color: t.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              for (final (label, before, next, warn) in rows)
                TableRow(
                  decoration: warn
                      ? BoxDecoration(color: t.warningSurface)
                      : null,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        label,
                        style: AppTypeScale.controlStrong.copyWith(
                          color: t.textBody,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(before, style: cell),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: next == null
                          ? Text(
                              notSet,
                              style: cell.copyWith(color: t.textMuted),
                            )
                          : Text(
                              next,
                              style: cell.copyWith(
                                color: warn ? t.warning : t.textBody,
                              ),
                            ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
          Text(
            l10n.aiSwitchFooter,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton.primary(
          label: l10n.aiSwitchConfirm,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
