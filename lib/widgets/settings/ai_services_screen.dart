import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_service_profile.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/connection_check.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';
import 'model_parameters_page.dart';

/// Header-less two-pane AI services manager (list + detail). Designed for
/// embedding inside the Settings shell.
class AiServicesView extends StatefulWidget {
  const AiServicesView({super.key});

  @override
  State<AiServicesView> createState() => _AiServicesViewState();
}

class _AiServicesViewState extends State<AiServicesView> {
  String? _selectedId;

  /// 模型参数展开页占满内容区（03b）：滑块要一整条轨道，挤在详情右半边里九个
  /// 刻度会叠在一起。所以展开时服务列表让位。
  bool _parametersOpen = false;

  @override
  void initState() {
    super.initState();
    final profiles = context.read<AiProfilesService>();
    _selectedId =
        profiles.activeId ??
        (profiles.services.isNotEmpty ? profiles.services.first.id : null);
  }

  AiServiceProfile? _resolve(List<AiServiceProfile> services) {
    for (final s in services) {
      if (s.id == _selectedId) return s;
    }
    return services.isNotEmpty ? services.first : null;
  }

  void _addService() {
    final l10n = AppLocalizations.of(context)!;
    final profile = AiServiceProfile.create(name: l10n.newServiceName);
    context.read<AiProfilesService>().add(profile);
    setState(() => _selectedId = profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<AiProfilesService>();
    final services = profiles.services;
    final selected = _resolve(services);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_parametersOpen)
          SizedBox(
            width: 360,
            child: _ServiceList(
              services: services,
              selectedId: selected?.id,
              activeId: profiles.activeId,
              onSelect: (id) => setState(() => _selectedId = id),
              onAdd: _addService,
            ),
          ),
        Expanded(
          child: selected == null
              ? _EmptyDetail(onAdd: _addService)
              : _ServiceDetail(
                  key: ValueKey(selected.id),
                  profile: selected,
                  isActive: selected.id == profiles.activeId,
                  showParameters: _parametersOpen,
                  onShowParameters: (v) => setState(() => _parametersOpen = v),
                ),
        ),
      ],
    );
  }
}

/// Visual identity (color + glyph) for a provider's badge.
({Color color, String glyph}) _badge(AiProviderType provider) =>
    switch (provider) {
      AiProviderType.googleGenAi => (
        color: AppPalette.vendorGoogle.first,
        glyph: 'G',
      ),
      AiProviderType.openAi => (
        color: AppPalette.vendorOpenAi.first,
        glyph: '◆',
      ),
    };

String _protocolLabel(BuildContext context, AiProviderType p) {
  final l10n = AppLocalizations.of(context)!;
  return p == AiProviderType.googleGenAi
      ? l10n.protocolGoogle
      : l10n.protocolOpenAi;
}

// ── Left: service list ──────────────────────────────────────────────────────

class _ServiceList extends StatelessWidget {
  final List<AiServiceProfile> services;
  final String? selectedId;
  final String? activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  const _ServiceList({
    required this.services,
    required this.selectedId,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    // 6.1：列表 `padding 18 14` · gap 10，虚线「添加另一个端点」是**列表的最后
    // 一张卡**，不是钉在底边的按钮 —— 钉在底边时，两张服务卡的下面会空出半屏，
    // 那颗按钮看起来就不像「再加一个」而像「这一栏的操作」。
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md12,
        vertical: AppSpacing.lg,
      ),
      itemCount: services.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        if (i == services.length) {
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadii.panel),
            onTap: onAdd,
            child: DottedBorderBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.addAnotherEndpoint,
                        style: AppTypeScale.control.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final s = services[i];
        return _ServiceCard(
          profile: s,
          selected: s.id == selectedId,
          active: s.id == activeId,
          onTap: () => onSelect(s.id),
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final AiServiceProfile profile;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.profile,
    required this.selected,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = context.tokens;
    final badge = _badge(profile.provider);

    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.16) : glass.cardFill,
      borderRadius: BorderRadius.circular(AppRadii.panel),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.panel),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.6)
                  : glass.stroke,
              width: selected ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BadgeIcon(color: badge.color, glyph: badge.glyph),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: AppTypeScale.sizeTitle,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _host(profile.endpoint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: AppTypeScale.sizeCaption,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(profile: profile, active: active),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Model ids can be long; let this chip shrink + ellipsize so
                  // the row never overflows the fixed-width list column.
                  Flexible(
                    child: _MiniChip(
                      profile.model.isEmpty ? '—' : profile.model,
                      mono: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniChip(_protocolLabel(context, profile.provider)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _host(String endpoint) {
    var e = endpoint.replaceFirst(RegExp(r'^https?://'), '');
    return e.isEmpty ? '—' : e;
  }
}

class _StatusBadge extends StatelessWidget {
  final AiServiceProfile profile;
  final bool active;
  const _StatusBadge({required this.profile, required this.active});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (Color c, String label) = !profile.isComplete
        ? (AppPalette.warning, l10n.statusOffline)
        : active
        ? (AppPalette.success, l10n.statusActive)
        : (Theme.of(context).colorScheme.onSurfaceVariant, l10n.statusStandby);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: AppTypeScale.sizeCaption,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Right: detail editor ────────────────────────────────────────────────────

class _ServiceDetail extends StatefulWidget {
  final AiServiceProfile profile;
  final bool isActive;

  /// 模型参数展开页是否占着内容区。状态挂在父级，因为展开时要连服务列表一起收。
  final bool showParameters;
  final ValueChanged<bool> onShowParameters;

  const _ServiceDetail({
    super.key,
    required this.profile,
    required this.isActive,
    required this.showParameters,
    required this.onShowParameters,
  });

  @override
  State<_ServiceDetail> createState() => _ServiceDetailState();
}

class _ServiceDetailState extends State<_ServiceDetail> {
  late AiProviderType _provider;
  late TextEditingController _name;
  late TextEditingController _endpoint;
  late TextEditingController _apiKey;
  late TextEditingController _model;
  late TextEditingController _contextWindow;
  late TextEditingController _maxOutput;

  /// Sampling overrides as typed. Blank follows the model family's preset.
  late final Map<_Sampling, TextEditingController> _sampling;
  late bool _thinking;
  bool _obscureKey = true;

  bool _testing = false;
  bool? _testOk;

  /// What the last successful test found the server reporting. Shown beside
  /// the fields rather than written into them: a loaded size and a model
  /// maximum are different claims, and only the user knows which one the
  /// budget should follow.
  ModelLimits? _detected;

  /// The last successful test, for what it showed about reasoning and the
  /// server: the thinking status line and the Ollama note read it.
  AiConnectionCheckResult? _lastCheck;

  /// The recorded tool-calling check. Carried through [_config] so saving an
  /// edited field does not erase it; [AiConfig.supportsTools] already ignores
  /// it once the endpoint or model no longer matches.
  ToolSupport? _toolSupport;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _provider = p.provider;
    _name = TextEditingController(text: p.name);
    _endpoint = TextEditingController(text: p.endpoint);
    _apiKey = TextEditingController(text: p.apiKey);
    _model = TextEditingController(text: p.model);
    _contextWindow = TextEditingController(
      text: p.contextWindow?.toString() ?? '',
    );
    _maxOutput = TextEditingController(
      text: p.maxOutputTokens?.toString() ?? '',
    );
    _sampling = {
      _Sampling.temperature: TextEditingController(text: _text(p.temperature)),
      _Sampling.topP: TextEditingController(text: _text(p.topP)),
      _Sampling.topK: TextEditingController(text: _text(p.topK)),
      _Sampling.minP: TextEditingController(text: _text(p.minP)),
      _Sampling.presencePenalty: TextEditingController(
        text: _text(p.presencePenalty),
      ),
      _Sampling.repeatPenalty: TextEditingController(
        text: _text(p.repeatPenalty),
      ),
    };
    _thinking = p.thinkingEnabled;
    _toolSupport = p.toolSupport;
  }

  static String _text(num? value) => value?.toString() ?? '';

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    _model.dispose();
    _contextWindow.dispose();
    _maxOutput.dispose();
    for (final controller in _sampling.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _decimal(_Sampling field) => AiConfig.decimal(_sampling[field]!.text);

  AiConfig _config() => AiConfig(
    provider: _provider,
    endpoint: _endpoint.text.trim(),
    apiKey: _apiKey.text.trim(),
    model: _model.text.trim(),
    temperature: _decimal(_Sampling.temperature),
    topP: _decimal(_Sampling.topP),
    topK: AiConfig.tokenCount(_sampling[_Sampling.topK]!.text),
    minP: _decimal(_Sampling.minP),
    presencePenalty: _decimal(_Sampling.presencePenalty),
    repeatPenalty: _decimal(_Sampling.repeatPenalty),
    thinkingEnabled: _thinking,
    contextWindow: AiConfig.tokenCount(_contextWindow.text),
    maxOutputTokens: AiConfig.tokenCount(_maxOutput.text),
    toolSupport: _toolSupport,
  );

  void _persist() {
    final config = _config();
    context.read<AiProfilesService>().update(
      AiServiceProfile.fromConfig(
        id: widget.profile.id,
        name: _name.text,
        config: config,
      ),
    );
    if (widget.isActive) {
      context.read<AiService>().updateConfig(config);
    }
  }

  void _resetSampling() {
    setState(() {
      for (final controller in _sampling.values) {
        controller.clear();
      }
    });
    _persist();
  }

  void _setThinking(bool value) {
    setState(() {
      _thinking = value;
      // The last test's verdict was about the other mode.
      _lastCheck = null;
    });
    _persist();
  }

  Future<void> _test() async {
    _persist();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final config = _config();
    if (!config.isComplete) {
      setState(() => _testOk = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.connectionIncomplete)),
      );
      return;
    }
    final ai = context.read<AiService>();
    setState(() {
      _testing = true;
      _testOk = null;
    });
    AiConnectionCheckResult? result;
    String? error;
    try {
      result = await ai.testConnection(config);
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    final checked = result;
    setState(() {
      _testing = false;
      _testOk = checked != null;
      if (checked != null) {
        _detected = checked.limits;
        _lastCheck = checked;
        if (checked.supportsTools case final probe
            when probe != ToolProbe.inconclusive) {
          _toolSupport = ToolSupport(
            fingerprint: config.toolFingerprint,
            supported: probe == ToolProbe.supported,
          );
        }
      }
    });
    // Every profile on this endpoint and model shares the answer, and the
    // live service must see it before the next organize or scrape. A probe
    // that never completed is not an answer and is not recorded.
    if (checked != null && checked.supportsTools != ToolProbe.inconclusive) {
      context.read<AiProfilesService>().recordToolSupport(
        config,
        checked.supportsTools == ToolProbe.supported,
      );
      _persist();
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          checked == null
              ? l10n.connectionFailed(error ?? '')
              : _describeCheck(l10n, checked),
        ),
      ),
    );
  }

  static String _describeCheck(
    AppLocalizations l10n,
    AiConnectionCheckResult result,
  ) {
    var reply = result.reply.replaceAll(RegExp(r'\s+'), ' ');
    if (reply.length > 120) reply = '${reply.substring(0, 120)}…';
    final text = l10n.connectionOkReply(
      result.latency.inMilliseconds,
      reply.isEmpty ? l10n.connectionEmptyReply : reply,
    );
    return result.truncated ? '$text\n${l10n.connectionTruncated}' : text;
  }

  void _useDetected(ModelLimits limits) {
    setState(() {
      if (limits.contextWindow != null) {
        _contextWindow.text = '${limits.contextWindow}';
      }
      if (limits.maxOutputTokens != null) {
        _maxOutput.text = '${limits.maxOutputTokens}';
      }
    });
    _persist();
  }

  /// Makes this profile the one every AI task uses.
  ///
  /// The list marked which profile was active but offered no way to change
  /// it, so a second profile could be added, edited and tested yet never
  /// actually run. Persist first: the stored active id and the live config
  /// must not disagree if the app closes between the two.
  Future<void> _activate() async {
    _persist();
    final profiles = context.read<AiProfilesService>();
    final ai = context.read<AiService>();
    await profiles.setActive(widget.profile.id);
    if (!mounted) return;
    ai.updateConfig(profiles.aiConfig);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final profiles = context.read<AiProfilesService>();
    final confirm = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: Text(l10n.deleteServiceTitle),
        content: Text(l10n.deleteServiceConfirm(widget.profile.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm == true) {
      profiles.delete(widget.profile.id);
    }
  }

  /// 上下文窗口，读自它自己的控制器 —— 滑块和输入框共用同一份真值。
  int? get _contextTokens => AiConfig.tokenCount(_contextWindow.text);

  void _setContextTokens(int? tokens) {
    setState(() => _contextWindow.text = tokens?.toString() ?? '');
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final badge = _badge(_provider);

    if (widget.showParameters) {
      return ModelParametersPage(
        serviceName: _name.text.isEmpty ? l10n.newServiceName : _name.text,
        model: _model.text.trim(),
        contextWindow: _contextTokens,
        onContextWindow: _setContextTokens,
        maxOutput: _maxOutput,
        onMaxOutputChanged: _persist,
        detectedCeiling: _detected?.contextWindow,
        onCollapse: () => widget.onShowParameters(false),
        sampling: _SamplingSection(
          preset: SamplingPresets.forModel(_model.text),
          controllers: _sampling,
          thinking: _thinking,
          lastCheck: _lastCheck,
          onChanged: _persist,
          onThinkingChanged: _setThinking,
          onReset: _resetSampling,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 24, 24),
      children: [
        // Header: identity + actions.
        Row(
          children: [
            _BadgeIcon(color: badge.color, glyph: badge.glyph, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name.text.isEmpty ? l10n.newServiceName : _name.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // 1.2 的字阶里详情页主标题就是 heading（22 / 700）；手写一个
                    // w800 只是又造了一级不在字阶上的字重。
                    style: AppTypeScale.heading,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.aiServiceDetailHint,
                    style: TextStyle(
                      fontSize: AppTypeScale.sizeBody,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.isActive) ...[
              OutlinedButton.icon(
                onPressed: _activate,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(l10n.useThisService),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            OutlinedButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l10n.delete),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TestButton(
              testing: _testing,
              ok: _testOk,
              onPressed: _testing ? null : _test,
            ),
          ],
        ),
        if (_config().supportsTools case final tools?) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                tools ? Icons.build_circle_outlined : Icons.block,
                size: 16,
                color: tools ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tools ? l10n.toolsSupported : l10n.toolsUnsupported,
                  style: TextStyle(
                    fontSize: AppTypeScale.sizeBody,
                    color: tools ? scheme.onSurfaceVariant : scheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),

        // Endpoint protocol segmented control.
        _FieldLabel(l10n.endpointProtocol),
        const SizedBox(height: 10),
        _ProtocolSegmented(
          value: _provider,
          onChanged: (p) {
            setState(() => _provider = p);
            _persist();
          },
        ),
        const SizedBox(height: 22),

        // Name + Base URL.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Field(
                label: l10n.displayName,
                controller: _name,
                onChanged: (_) {
                  setState(() {});
                  _persist();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Field(
                label: l10n.baseUrl,
                controller: _endpoint,
                mono: true,
                onChanged: (_) => _persist(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // API key + default model.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Field(
                label: l10n.apiKey,
                controller: _apiKey,
                mono: true,
                obscure: _obscureKey,
                hint: _provider.requiresApiKey ? null : l10n.apiKeyOptionalHint,
                onChanged: (_) => _persist(),
                trailing: GestureDetector(
                  onTap: () => setState(() => _obscureKey = !_obscureKey),
                  child: Text(
                    _obscureKey ? l10n.showKey : l10n.hideKey,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: AppTypeScale.sizeBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Field(
                label: l10n.defaultModel,
                controller: _model,
                mono: true,
                onChanged: (_) {
                  // The preset label and placeholders follow the model id.
                  setState(() {});
                  _persist();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 6.1 的「模型参数」摘要行：上下文、最大输出与采样都收进展开页，详情页
        // 只留一行摘要。展开页要一整条滑轨（03b），所以它占满内容区。
        ModelParametersSummary(
          contextWindow: AiConfig.tokenCount(_contextWindow.text),
          maxOutput: AiConfig.tokenCount(_maxOutput.text),
          presetLabel:
              SamplingPresets.forModel(_model.text)?.label ??
              l10n.samplingNoPreset,
          thinking: _thinking,
          onExpand: () => widget.onShowParameters(true),
        ),
        const SizedBox(height: 10),
        if (_detected case final detected?)
          _DetectedLimits(
            limits: detected,
            onUse: () => _useDetected(detected),
          ),
        const SizedBox(height: 24),

        // Usage stats (live for the active service).
        _UsageCard(active: widget.isActive),
      ],
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyDetail({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 56,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.selectServiceHint,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(l10n.addService),
          ),
        ],
      ),
    );
  }
}

// ── Small building blocks ───────────────────────────────────────────────────

class _BadgeIcon extends StatelessWidget {
  final Color color;
  final String glyph;
  final double size;
  const _BadgeIcon({required this.color, required this.glyph, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  final bool mono;
  const _MiniChip(this.text, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: AppTypeScale.sizeCaption,
          fontFamily: mono ? 'monospace' : null,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppTypeScale.sizeControl,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A labelled, card-styled input matching the mockup's field treatment.
class _Field extends StatelessWidget {
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

  /// 值域，右对齐在标签行上（6.1 的采样参数格）。知道「0 – 2」比知道字段叫什么
  /// 更能决定该填多少。
  final String? range;

  const _Field({
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
  });

  @override
  Widget build(BuildContext context) {
    final glass = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: _FieldLabel(label)),
              if (range != null)
                Text(
                  range!,
                  style: AppTypeScale.monoTiny.copyWith(color: glass.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 6),
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
                  style: TextStyle(
                    fontSize: AppTypeScale.sizeTitle,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

/// What the last connection test found the server reporting, with a way to
/// adopt it. Only the user can say whether a model's maximum is really what
/// they loaded, so nothing is filled in without this click.
class _DetectedLimits extends StatelessWidget {
  final ModelLimits limits;
  final VoidCallback onUse;
  const _DetectedLimits({required this.limits, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            found ? Icons.radar_rounded : Icons.help_outline_rounded,
            size: 16,
            color: found ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              found ? parts.join(' · ') : l10n.limitsNotDetected,
              style: TextStyle(
                fontSize: AppTypeScale.sizeControl,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (found)
            TextButton(onPressed: onUse, child: Text(l10n.useDetectedValue)),
        ],
      ),
    );
  }
}

enum _Sampling { temperature, topP, topK, minP, presencePenalty, repeatPenalty }

/// A service's sampling settings: which preset applies, one field per
/// parameter with the preset's value as its placeholder, and the thinking
/// switch with what the last connection test showed.
///
/// Every field is optional on purpose. A blank one follows the preset, so the
/// recommended values keep working after a model is swapped for another
/// family; typing a value is an explicit override.
class _SamplingSection extends StatelessWidget {
  final SamplingPreset? preset;
  final Map<_Sampling, TextEditingController> controllers;
  final bool thinking;
  final AiConnectionCheckResult? lastCheck;
  final VoidCallback onChanged;
  final ValueChanged<bool> onThinkingChanged;
  final VoidCallback onReset;

  const _SamplingSection({
    required this.preset,
    required this.controllers,
    required this.thinking,
    required this.lastCheck,
    required this.onChanged,
    required this.onThinkingChanged,
    required this.onReset,
  });

  static const _rows = [
    (_Sampling.temperature, _Sampling.topP),
    (_Sampling.topK, _Sampling.minP),
    (_Sampling.presencePenalty, _Sampling.repeatPenalty),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = context.tokens;
    final preset = this.preset;
    final reasons = preset?.reasons(requested: thinking) ?? thinking;
    final values = preset?.valuesFor(thinking: reasons);
    final status = _thinkingStatus(l10n, reasons);
    final note = TextStyle(
      fontSize: AppTypeScale.sizeCaption,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    );

    String label(_Sampling field) => switch (field) {
      _Sampling.temperature => l10n.temperature,
      _Sampling.topP => l10n.samplingTopP,
      _Sampling.topK => l10n.samplingTopK,
      _Sampling.minP => l10n.samplingMinP,
      _Sampling.presencePenalty => l10n.samplingPresencePenalty,
      _Sampling.repeatPenalty => l10n.samplingRepeatPenalty,
    };

    // What a blank field sends: the preset's value for the mode reasoning
    // will run in, or — outside every preset — the old fixed temperature.
    String placeholder(_Sampling field) {
      final value = switch (field) {
        _Sampling.temperature =>
          values?.temperature ??
              (preset == null ? ResolvedSampling.legacyTemperature : null),
        _Sampling.topP => values?.topP,
        _Sampling.topK => values?.topK,
        _Sampling.minP => values?.minP,
        _Sampling.presencePenalty => values?.presencePenalty,
        _Sampling.repeatPenalty => values?.repeatPenalty,
      };
      return value == null ? l10n.samplingDefault : '$value';
    }

    // 6.1 给的六个值域。它们是模型这一侧的约定，不随语言变，所以不进 ARB。
    const ranges = {
      _Sampling.temperature: '0 – 2',
      _Sampling.topP: '0 – 1',
      _Sampling.topK: '1 – 200',
      _Sampling.minP: '0 – 1',
      _Sampling.presencePenalty: '-2 – 2',
      _Sampling.repeatPenalty: '1 – 2',
    };

    Widget field(_Sampling which) => _Field(
      label: label(which),
      controller: controllers[which]!,
      mono: true,
      hint: placeholder(which),
      range: ranges[which],
      digitsOnly: which == _Sampling.topK,
      decimal: which != _Sampling.topK,
      onChanged: (_) => onChanged(),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FieldLabel(l10n.samplingTitle),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preset == null
                      ? l10n.samplingNoPreset
                      : l10n.samplingPresetMatched(preset.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypeScale.sizeControl,
                    color: scheme.onSurfaceVariant,
                  ),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.thinkingMode,
                      style: const TextStyle(
                        fontSize: AppTypeScale.sizeBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(l10n.thinkingModeHint, style: note),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 6.1 的 38 x 22 开关，不是 Material 的 Switch。
              AppToggle(
                value: reasons,
                width: 38,
                height: 22,
                // Only a family whose reasoning really can be switched gets a
                // live control; anything else would be a switch that does
                // nothing.
                onChanged: (preset?.thinkingIsOptional ?? false)
                    ? onThinkingChanged
                    : null,
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 6),
            Text(
              status.text,
              style: note.copyWith(
                color: status.warning ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (final (left, right) in _rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field(left)),
                const SizedBox(width: 12),
                Expanded(child: field(right)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(l10n.samplingNote, style: note),
          if (preset?.needsSystemPrompt ?? false) ...[
            const SizedBox(height: 6),
            Text(l10n.presetNeedsSystemPrompt, style: note),
          ],
          if (lastCheck?.serverKind == ServerKind.ollama) ...[
            const SizedBox(height: 6),
            Text(l10n.ollamaIgnoresSampling, style: note),
          ],
        ],
      ),
    );
  }

  /// A line under the switch: what the family allows, or — for a family
  /// whose reasoning can be switched off — whether the last test showed it
  /// actually was. That second case is the one worth a line, because servers
  /// ignore the fields that turn it off without saying so.
  ({String text, bool warning})? _thinkingStatus(
    AppLocalizations l10n,
    bool reasons,
  ) {
    switch (preset?.thinkingControl) {
      case ThinkingControl.alwaysOn:
        return (text: l10n.thinkingAlwaysOn, warning: false);
      case ThinkingControl.effortOnly:
        return (text: l10n.thinkingEffortOnly, warning: false);
      default:
        break;
    }
    final check = lastCheck;
    if (check == null || reasons || !(preset?.thinkingIsOptional ?? false)) {
      return null;
    }
    return check.reasoned
        ? (text: l10n.thinkingStillOn, warning: true)
        : (text: l10n.thinkingVerifiedOff, warning: false);
  }
}

class _ProtocolSegmented extends StatelessWidget {
  final AiProviderType value;
  final ValueChanged<AiProviderType> onChanged;
  const _ProtocolSegmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glass = context.tokens;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: Row(
        children: [
          _seg(context, AiProviderType.openAi, '◆  ${l10n.protocolOpenAi}'),
          const SizedBox(width: 6),
          _seg(
            context,
            AiProviderType.googleGenAi,
            'G  ${l10n.protocolGoogle}',
          ),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, AiProviderType p, String label) {
    final scheme = Theme.of(context).colorScheme;
    final on = p == value;
    return Expanded(
      child: Material(
        color: on ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.field),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.field),
          onTap: () => onChanged(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final bool testing;
  final bool? ok;
  final VoidCallback? onPressed;
  const _TestButton({
    required this.testing,
    required this.ok,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.field),
        gradient: const LinearGradient(
          colors: [AppPalette.success, AppPalette.success],
        ),
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        icon: testing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                ok == null
                    ? Icons.bolt
                    : (ok! ? Icons.check_circle : Icons.error),
                size: 18,
              ),
        label: Text(l10n.testConnection),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final bool active;
  const _UsageCard({required this.active});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glass = context.tokens;
    final ai = context.watch<AiService>();

    final tokens = active ? '${ai.totalTokens}' : '—';
    final reqs = active ? '${ai.requestCount}' : '—';
    final latency = active && ai.avgLatencyMs > 0
        ? '${ai.avgLatencyMs} ms'
        : '—';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stat(context, l10n.tokensThisSession, tokens),
          const SizedBox(width: 32),
          _stat(context, l10n.requests, reqs),
          const SizedBox(width: 32),
          _stat(context, l10n.avgLatency, latency),
          const Spacer(),
          SizedBox(
            width: 120,
            height: 48,
            child: _Sparkline(values: active ? ai.recentLatencies : const []),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTypeScale.sizeControl,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          // 6.1 的用量数值是 mono 18/600；18 不在 1.2 的字阶上，取 16。
          value,
          style: const TextStyle(
            fontFamily: AppTypeScale.mono,
            fontSize: AppTypeScale.sizeSubheading,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Tiny bar chart of recent latencies; renders flat placeholder bars when empty.
class _Sparkline extends StatelessWidget {
  final List<int> values;
  const _Sparkline({required this.values});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = values.isEmpty ? List<int>.filled(8, 1) : values;
    final maxV = data.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 31);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < data.length; i++) ...[
          Expanded(
            child: FractionallySizedBox(
              heightFactor: values.isEmpty
                  ? 0.18
                  : (data[i] / maxV).clamp(0.12, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
              ),
            ),
          ),
          if (i != data.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// A rounded rectangle with a dashed border (for the "add endpoint" button).
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        radius: 14,
      ),
      child: child,
    );
  }
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
