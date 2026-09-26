import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_profiles_service.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/learned_behaviour.dart';
import '../../services/ai/platform_profiles.dart';
import '../../theme/design_tokens.dart';
import 'ai_services_screen.dart';
import 'ai_settings_widgets.dart';

/// What a cell of the matrix says.
enum CapabilityState {
  /// Measured, or declared by the protocol itself.
  works,

  /// Not measured yet: allowed, and probed before it is relied on.
  unmeasured,

  /// Cannot be sent: not on this platform, not by this model, not in this
  /// build, or not allowed by the user.
  unavailable,
}

typedef CapabilityCell = ({CapabilityState state, String text});

/// The capabilities of [model] on each route of [channel] (CapabilityMatrix
/// artboard): rows are capabilities, columns the routes the platform offers.
///
/// The user's authorisation (image and video input) and whether a route can
/// carry something are different questions, and the matrix keeps them apart:
/// "not allowed" is the user's switch, "not in this build" is the app's.
class AiCapabilityMatrixPage extends StatelessWidget {
  final String channelId;
  final String modelId;
  final VoidCallback onBack;

  const AiCapabilityMatrixPage({
    super.key,
    required this.channelId,
    required this.modelId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final entry = context.watch<AiProfilesService>().modelById(modelId)!;
    final channel = entry.channel;
    final model = entry.model;
    final current = channel.configFor(model).provider;
    final protocols = [
      ...{
        ...channel.platform.routes.keys,
        for (final route in channel.routes) route.protocol,
      },
    ];

    final rows = <(String, String, CapabilityCell Function(AiProviderType))>[
      (
        l10n.aiCapTools,
        l10n.aiCapToolsHint,
        (p) => capabilityCell(l10n, channel, model, p, Capability.tools),
      ),
      (
        l10n.aiCapJson,
        l10n.aiCapJsonHint,
        (p) => capabilityCell(l10n, channel, model, p, Capability.json),
      ),
      (
        l10n.aiCapImage,
        model.imageInput ? l10n.aiCapAllowed : l10n.aiCapNotAllowed,
        (p) => capabilityCell(l10n, channel, model, p, Capability.image),
      ),
      (
        l10n.aiCapVideo,
        model.videoInput ? l10n.aiCapAllowed : l10n.aiCapNotAllowed,
        (p) => capabilityCell(l10n, channel, model, p, Capability.video),
      ),
      (
        l10n.aiCapThinkingOff,
        l10n.aiCapThinkingOffHint,
        (p) => capabilityCell(l10n, channel, model, p, Capability.thinkingOff),
      ),
      (
        l10n.aiCapUsage,
        l10n.aiCapUsageHint,
        (p) => capabilityCell(l10n, channel, model, p, Capability.usage),
      ),
    ];

    Color ink(CapabilityState state) => switch (state) {
      CapabilityState.works => t.success,
      CapabilityState.unmeasured => t.warning,
      CapabilityState.unavailable => t.textMuted,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiPageHeader(
          backLabel: model.upstream,
          onBack: onBack,
          title: l10n.aiCapabilityMatrix,
          subtitle: l10n.aiMatrixHint,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl24,
              0,
              AppSpacing.xl24,
              AppSpacing.xl24,
            ),
            children: [
              AiCard(
                padding: EdgeInsets.zero,
                child: Table(
                  columnWidths: const {0: FixedColumnWidth(200)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                    horizontalInside: BorderSide(color: t.stroke),
                  ),
                  children: [
                    TableRow(
                      children: [
                        const SizedBox.shrink(),
                        for (final p in protocols)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.md12),
                            child: Column(
                              children: [
                                ProtocolChip(
                                  protocol: p,
                                  state: p == current
                                      ? ProtocolChipState.current
                                      : channel.routeFor(p) != null
                                      ? ProtocolChipState.enabled
                                      : ProtocolChipState.offered,
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  p == current
                                      ? l10n.aiColCurrent
                                      : channel.routeFor(p) != null
                                      ? l10n.aiColEnabled
                                      : l10n.aiColOffered,
                                  style: AppTypeScale.caption.copyWith(
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    for (final (label, hint, cell) in rows)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.md12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: AppTypeScale.controlStrong.copyWith(
                                    color: t.textTitle,
                                  ),
                                ),
                                Text(
                                  hint,
                                  style: AppTypeScale.caption.copyWith(
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final p in protocols)
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md12),
                              color: p == current
                                  ? t.accent.withValues(alpha: 0.06)
                                  : null,
                              alignment: Alignment.center,
                              child: Builder(
                                builder: (_) {
                                  final value = cell(p);
                                  return Text(
                                    value.text,
                                    textAlign: TextAlign.center,
                                    style: AppTypeScale.control.copyWith(
                                      color: ink(value.state),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md12),
              Text(
                l10n.aiMatrixFootnote,
                style: AppTypeScale.caption.copyWith(color: t.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum Capability { tools, json, image, video, thinkingOff, usage }

/// One cell: what [capability] looks like for [model] if it ran on
/// [protocol]. Pure, so the task pickers and the tests read the same answer.
CapabilityCell capabilityCell(
  AppLocalizations l10n,
  AiChannel channel,
  AiModelEntry model,
  AiProviderType protocol,
  Capability capability,
) {
  const works = CapabilityState.works;
  const unmeasured = CapabilityState.unmeasured;
  const unavailable = CapabilityState.unavailable;
  if (!protocolInBuild(protocol)) {
    return (state: unavailable, text: l10n.aiCellNotInBuild);
  }
  // `configFor` falls back to the primary route for a protocol the channel
  // lacks; an offered column must show that protocol, measured or not.
  final config =
      (channel.routeFor(protocol) != null
              ? channel
              : channel.copyWith(
                  routes: [
                    ...channel.routes,
                    AiRoute(protocol: protocol),
                  ],
                ))
          .configFor(model.switchedTo(protocol));
  // The route on a channel that does not have it yet still has a URL, so
  // what the provider learned there (nothing, usually) can be read.
  final learned = channel.routeFor(protocol) == null
      ? null
      : AiService.providerFor(config).learned;
  switch (capability) {
    case Capability.tools:
      return switch (config.supportsTools) {
        true => (state: works, text: l10n.aiCellMeasured),
        false => (state: unavailable, text: l10n.aiCellUnsupported),
        null => (state: unmeasured, text: l10n.aiCellUnmeasured),
      };
    case Capability.json:
      // Anthropic has no JSON parameter: the prompt asks, the parser holds.
      if (protocol == AiProviderType.anthropic) {
        return (state: works, text: l10n.aiCellPromptOnly);
      }
      final mode = learned?.jsonMode;
      if (mode != null) return (state: works, text: l10n.aiCellLearned(mode));
      return (state: unmeasured, text: l10n.aiCellParameter);
    case Capability.image || Capability.video:
      final allowed = capability == Capability.image
          ? model.imageInput
          : model.videoInput;
      if (!allowed) return (state: unavailable, text: l10n.aiCellNotAllowed);
      // Every adapter can carry an image part; whether this model reads it
      // is only known once it has been tried. Video goes as frames — no
      // protocol's native video part is sent (not measured on any of them).
      if (capability == Capability.video) {
        return (state: unmeasured, text: l10n.aiCellAsFrames);
      }
      return (
        state: unmeasured,
        text: l10n.aiCellSentAs(switch (protocol) {
          AiProviderType.openAi => 'image_url',
          AiProviderType.googleGenAi => 'inlineData',
          AiProviderType.anthropic => 'image',
          AiProviderType.openAiResponses => 'input_image',
        }),
      );
    case Capability.thinkingOff:
      final (:route, :field) = PlatformProfiles.reasoningRouteFor(
        config,
        learned ?? LearnedBehaviour.empty,
      );
      switch (route) {
        // Messages thinking is off unless asked for, whether or not on was
        // refused.
        case ReasoningRoute.protocolField
            when protocol == AiProviderType.anthropic:
          return (state: works, text: l10n.aiCellDefaultOff);
        // A switch sends off in its own words; a refused on changes nothing
        // there.
        case ReasoningRoute.platformField:
        case ReasoningRoute.onRefused:
          return (state: works, text: l10n.aiCellSwitch(field!));
        // Responses asks for `effort: none`. Sending it is not the same as
        // it being honoured — a relay can rewrite it to medium — so it stays
        // unmeasured; the connection test's "still reasoned" is the judge.
        case ReasoningRoute.protocolField:
          return (state: unmeasured, text: l10n.aiCellProtocolSwitch(field!));
        // Nothing is sent for off. Only Messages, whose thinking is off
        // unless asked for, still gets what off means.
        case ReasoningRoute.offRefused:
        case ReasoningRoute.offToDefault:
        case ReasoningRoute.refused:
          return (
            state: route == ReasoningRoute.refused && messagesDefaultOff(config)
                ? works
                : unavailable,
            text: reasoningRefusalText(l10n, route, config)!,
          );
        case ReasoningRoute.ladder:
          // Only ladder steps count: a route key outlives its channel's
          // platform, so a switch refused under one can still be on record
          // here.
          final tried = learned?.thinkingOffTried ?? const <String>{};
          final steps = tried.where((w) => w != LearnedBehaviour.dialectOff);
          return steps.length >= 2
              ? (state: unavailable, text: l10n.aiCellLadderExhausted)
              : (state: unmeasured, text: l10n.aiCellLadder);
      }
    case Capability.usage:
      return (state: works, text: l10n.aiCellProtocolUsage);
  }
}
