import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_profiles_service.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/connection_check.dart';
import '../../services/ai/platform_profiles.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';
import 'ai_diagnostics_page.dart';
import 'ai_route_switch_dialog.dart';
import 'ai_services_screen.dart';
import 'ai_settings_widgets.dart';
import 'model_parameter_cards.dart';
import 'settings_controls.dart';

/// One model (ModelEdit artboard): the route it takes, what belongs to the
/// model whatever the route, what belongs to this route only, and a preview
/// of the request those settings produce.
class AiModelPage extends StatefulWidget {
  final String channelId;
  final String modelId;
  final VoidCallback onBack;
  final VoidCallback onMatrix;
  final VoidCallback onDiagnostics;

  const AiModelPage({
    super.key,
    required this.channelId,
    required this.modelId,
    required this.onBack,
    required this.onMatrix,
    required this.onDiagnostics,
  });

  @override
  State<AiModelPage> createState() => _AiModelPageState();
}

class _AiModelPageState extends State<AiModelPage> {
  late final TextEditingController _upstream;
  final _maxOutput = TextEditingController();
  late final Map<SamplingField, TextEditingController> _sampling = {
    for (final field in SamplingField.values) field: TextEditingController(),
  };

  /// The route the route-scoped controllers were last filled from.
  AiProviderType? _loadedRoute;

  bool _testing = false;
  AiConnectionCheckResult? _lastCheck;

  ChannelModel get _entry =>
      context.read<AiProfilesService>().modelById(widget.modelId)!;

  @override
  void initState() {
    super.initState();
    final entry = _entry;
    _upstream = TextEditingController(text: entry.model.upstream);
    _loadRoute(entry);
  }

  /// Fills the route-scoped fields from the model's current route. Called
  /// again after a switch: the other route's values are its own.
  void _loadRoute(ChannelModel entry) {
    final protocol = entry.channel.configFor(entry.model).provider;
    final params = entry.model.params[protocol] ?? RouteParams.empty;
    String text(num? v) => v?.toString() ?? '';
    _maxOutput.text = text(params.maxOutputTokens);
    _sampling[SamplingField.temperature]!.text = text(params.temperature);
    _sampling[SamplingField.topP]!.text = text(params.topP);
    _sampling[SamplingField.topK]!.text = text(params.topK);
    _sampling[SamplingField.minP]!.text = text(params.minP);
    _sampling[SamplingField.presencePenalty]!.text = text(
      params.presencePenalty,
    );
    _sampling[SamplingField.repeatPenalty]!.text = text(params.repeatPenalty);
    _loadedRoute = protocol;
  }

  @override
  void dispose() {
    _upstream.dispose();
    _maxOutput.dispose();
    for (final controller in _sampling.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveModel(AiModelEntry model) async {
    final profiles = context.read<AiProfilesService>();
    final ai = context.read<AiService>();
    await profiles.upsertModel(_entry.channel.id, model);
    ai.updateConfig(profiles.aiConfig);
  }

  /// Writes the route-scoped fields back under the route the model runs on
  /// — the one they were loaded from, which is the primary route when the
  /// model's own is gone — keeping its measured tool support.
  Future<void> _saveRoute({bool? thinking}) {
    final entry = _entry;
    final protocol = entry.channel.configFor(entry.model).provider;
    final current = entry.model.params[protocol] ?? RouteParams.empty;
    double? decimal(SamplingField f) => AiConfig.decimal(_sampling[f]!.text);
    return _saveModel(
      entry.model.copyWith(
        params: {
          ...entry.model.params,
          protocol: RouteParams(
            temperature: decimal(SamplingField.temperature),
            topP: decimal(SamplingField.topP),
            topK: AiConfig.tokenCount(_sampling[SamplingField.topK]!.text),
            minP: decimal(SamplingField.minP),
            presencePenalty: decimal(SamplingField.presencePenalty),
            repeatPenalty: decimal(SamplingField.repeatPenalty),
            thinkingEnabled: thinking ?? current.thinkingEnabled,
            maxOutputTokens: AiConfig.tokenCount(_maxOutput.text),
            toolSupport: current.toolSupport,
          ),
        },
      ),
    );
  }

  Future<void> _switch(AiProviderType to) async {
    final entry = _entry;
    final confirmed = await confirmRouteSwitch(
      context,
      channel: entry.channel,
      model: entry.model,
      to: to,
    );
    if (!confirmed || !mounted) return;
    // Re-read: a task may have recorded something on this model while the
    // dialog was open, and the copy from before it would erase that.
    await _saveModel(_entry.model.switchedTo(to));
    if (!mounted) return;
    setState(() {
      _lastCheck = null;
      _loadRoute(_entry);
    });
  }

  Future<void> _test() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _testing = true);
    final tested = _entry.model.route;
    final outcome = await runRouteTest(context, _entry);
    if (!mounted) return;
    setState(() {
      _testing = false;
      // Limits served on one route say nothing about another.
      _lastCheck = _entry.model.route == tested ? outcome.result : null;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome.result != null
              ? describeCheck(l10n, outcome.result!)
              : l10n.connectionFailed(outcome.error ?? ''),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final entry = _entry;
    final profiles = context.read<AiProfilesService>();
    final confirm = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: Text(l10n.aiDeleteModel),
        content: Text(l10n.aiDeleteModelConfirm(entry.model.upstream)),
        actions: [
          AppButton(
            label: l10n.cancel,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppButton(
            label: l10n.delete,
            kind: AppButtonKind.dangerSolid,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    widget.onBack();
    await profiles.deleteModel(entry.channel.id, entry.model.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final entry = context.watch<AiProfilesService>().modelById(widget.modelId)!;
    final channel = entry.channel;
    final model = entry.model;
    final config = channel.configFor(model);
    final protocol = config.provider;
    // The route changed under the page (a merge, a deleted route). The
    // fields are refilled after this frame: writing a controller mid-build
    // would rebuild its TextField during the build.
    if (_loadedRoute != protocol) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadRoute(_entry));
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiPageHeader(
          backLabel: channel.name,
          onBack: widget.onBack,
          title: model.upstream.isEmpty ? '—' : model.upstream,
          subtitle: '${l10n.aiAccessTitle} / ${channel.name}',
          actions: [
            AppButton.ghost(
              label: l10n.aiDiagnostics,
              onPressed: widget.onDiagnostics,
            ),
            AppButton(
              label: l10n.aiDeleteModel,
              icon: Icons.delete_outline,
              kind: AppButtonKind.danger,
              onPressed: _delete,
            ),
            AppButton.primary(
              label: l10n.aiTestRoute,
              icon: _testing ? null : Icons.bolt,
              onPressed: _testing || !protocolInBuild(protocol) ? null : _test,
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl24,
              0,
              AppSpacing.xl24,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl24),
                    children: [
                      _routeBar(l10n, t, channel, protocol),
                      const SizedBox(height: AppSpacing.md12),
                      _modelScope(l10n, t, model),
                      const SizedBox(height: AppSpacing.md12),
                      _routeScope(l10n, t, config, model),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  // ModelEdit artboard: the preview column, 380 of 1180.
                  width: 380,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl24),
                    child: _Preview(config: config),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _routeBar(
    AppLocalizations l10n,
    AppTokens t,
    AiChannel channel,
    AiProviderType current,
  ) => AiCard(
    title: l10n.aiRouteBar,
    note: l10n.aiRouteBarHint,
    trailing: AppButton.ghost(
      label: '${l10n.aiCapabilityMatrix} →',
      height: AppSizes.controlSm,
      onPressed: widget.onMatrix,
    ),
    child: Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final route in channel.routes)
          MouseRegion(
            cursor:
                route.protocol == current ||
                    !protocolInBuild(route.protocol) ||
                    _testing
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap:
                  route.protocol == current ||
                      !protocolInBuild(route.protocol) ||
                      _testing
                  ? null
                  : () => _switch(route.protocol),
              child: ProtocolChip(
                protocol: route.protocol,
                state: route.protocol == current
                    ? ProtocolChipState.current
                    : ProtocolChipState.enabled,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _modelScope(AppLocalizations l10n, AppTokens t, AiModelEntry model) {
    final detected = _lastCheck?.limits;
    return AiCard(
      title: l10n.aiScopeModel,
      note: l10n.aiScopeModelHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiField(
            label: l10n.aiUpstreamModel,
            controller: _upstream,
            mono: true,
            onChanged: (v) => _saveModel(_entry.model.copyWith(upstream: v)),
          ),
          const SizedBox(height: AppSpacing.md12),
          ParameterNotice(text: l10n.contextWindowNote, tint: t.warning),
          const SizedBox(height: AppSpacing.sm),
          ContextWindowCard(
            value: model.contextWindow,
            detectedCeiling: detected?.contextWindow,
            onChanged: (v) =>
                _saveModel(_entry.model.copyWith(contextWindow: () => v)),
          ),
          if (detected != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AiDetectedLimits(
              limits: detected,
              onUse: () async {
                if (detected.contextWindow case final window?) {
                  await _saveModel(
                    _entry.model.copyWith(contextWindow: () => window),
                  );
                }
                if (detected.maxOutputTokens case final output?) {
                  _maxOutput.text = '$output';
                  await _saveRoute();
                }
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md12),
          SettingsToggleRow(
            label: l10n.aiAllowImage,
            subtitle: l10n.aiAllowHint,
            value: model.imageInput,
            onChanged: (v) => _saveModel(_entry.model.copyWith(imageInput: v)),
          ),
          SettingsToggleRow(
            label: l10n.aiAllowVideo,
            value: model.videoInput,
            onChanged: (v) => _saveModel(_entry.model.copyWith(videoInput: v)),
          ),
        ],
      ),
    );
  }

  Widget _routeScope(
    AppLocalizations l10n,
    AppTokens t,
    AiConfig config,
    AiModelEntry model,
  ) {
    final provider = AiService.providerFor(config);
    final learned = provider.learned;
    final dialect = PlatformProfiles.dialectFor(config);
    final note = AppTypeScale.caption.copyWith(color: t.textMuted);

    Widget line(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // ModelEdit artboard: the 120px label column of the route scope.
            width: 120,
            child: AiFieldLabel(label),
          ),
          Expanded(child: value),
        ],
      ),
    );

    return AiCard(
      title: l10n.aiScopeRoute(protocolName(config.provider)),
      note: l10n.aiScopeRouteHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(
            l10n.aiThinkingDialect,
            Text(
              dialect != null
                  ? l10n.aiDialectField(dialect.field(thinking: false).key)
                  : l10n.aiRouteLadder,
              style: note.copyWith(color: t.textBody),
            ),
          ),
          line(
            l10n.aiParamTools,
            Text(switch (config.supportsTools) {
              true => l10n.aiToolsMeasured,
              false => l10n.aiToolsMeasuredNo,
              null => l10n.aiToolsNotMeasured,
            }, style: note.copyWith(color: t.textBody)),
          ),
          line(
            l10n.aiStructuredOutput,
            Text(
              learned.jsonMode != null
                  ? l10n.aiStructuredLearned(learned.jsonMode!)
                  : l10n.aiStructuredUnknown,
              style: note.copyWith(color: t.textBody),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MaxOutputCard(
            controller: _maxOutput,
            contextWindow: model.contextWindow,
            onChanged: _saveRoute,
          ),
          if (learned.maxCompletionTokens) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${l10n.aiSendsAs('max_completion_tokens')} · ${l10n.aiLearnedTag}',
              style: note,
            ),
          ],
          const SizedBox(height: AppSpacing.md12),
          AiSamplingSection(
            preset: SamplingPresets.forModel(model.upstream),
            controllers: _sampling,
            thinking: config.thinkingEnabled,
            platformSwitch: dialect != null,
            lastReasoned: _lastCheck?.reasoned,
            serverKind: _lastCheck?.serverKind,
            refused: learned.rejectedFields,
            onChanged: _saveRoute,
            onThinkingChanged: (v) {
              setState(() => _lastCheck = null);
              _saveRoute(thinking: v);
            },
            onReset: () {
              for (final controller in _sampling.values) {
                controller.clear();
              }
              _saveRoute();
            },
          ),
        ],
      ),
    );
  }
}

/// The request this model's settings produce for an organize turn, built by
/// the adapter itself so it cannot drift from what is really sent.
class _Preview extends StatelessWidget {
  final AiConfig config;
  const _Preview({required this.config});

  static const _messages = [SystemMessage('…'), UserMessage('…')];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return AiCard(
      title: l10n.aiPreviewTitle,
      fill: true,
      child: FutureBuilder<RequestPreview?>(
        // Keyed by the config's JSON so an edit rebuilds the preview.
        key: ValueKey(jsonEncode(config.toJson())),
        future: AiService.providerFor(config).previewRequest(
          messages: _messages,
          tools: const [AiConnectionCheck.toolProbe],
        ),
        builder: (context, snapshot) {
          final preview = snapshot.data;
          final text = preview == null
              ? (snapshot.connectionState == ConnectionState.done
                    ? l10n.aiPreviewUnavailable
                    : '')
              : _render(preview);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.aiPreviewHint,
                style: AppTypeScale.caption.copyWith(color: t.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: t.controlFill,
                    borderRadius: BorderRadius.circular(AppRadii.field),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: t.monoTiny.copyWith(color: t.textBody),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// URL, headers and body, with the conversation and tool list folded: the
  /// preview is about the fields around them.
  static String _render(RequestPreview preview) {
    final body = {
      for (final entry in preview.body.entries)
        entry.key: switch (entry.key) {
          'messages' || 'contents' || 'tools' => '[ … ]',
          'systemInstruction' => '{ … }',
          _ => entry.value,
        },
    };
    return [
      'POST ${preview.url}',
      for (final header in preview.headers.entries)
        '${header.key}: ${header.value}',
      '',
      const JsonEncoder.withIndent('  ').convert(body),
    ].join('\n');
  }
}
