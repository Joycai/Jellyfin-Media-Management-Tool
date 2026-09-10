import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_service_profile.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/connection_check.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_dialog.dart';

/// Header-less two-pane AI services manager (list + detail). Designed for
/// embedding inside the Settings shell.
class AiServicesView extends StatefulWidget {
  const AiServicesView({super.key});

  @override
  State<AiServicesView> createState() => _AiServicesViewState();
}

class _AiServicesViewState extends State<AiServicesView> {
  String? _selectedId;

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
        color: const Color(0xFF4285F4),
        glyph: 'G',
      ),
      AiProviderType.openAi => (color: const Color(0xFF10A37F), glyph: '◆'),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 20),
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              itemCount: services.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final s = services[i];
                return _ServiceCard(
                  profile: s,
                  selected: s.id == selectedId,
                  active: s.id == activeId,
                  onTap: () => onSelect(s.id),
                );
              },
            ),
          ),
          // Dashed "add another endpoint" affordance.
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onAdd,
            child: DottedBorderBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        l10n.addAnotherEndpoint,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final badge = _badge(profile.provider);

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.16)
          : glass.panelFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.6)
                  : glass.panelStroke,
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
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _host(profile.endpoint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
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
        ? (const Color(0xFFE0A030), l10n.statusOffline)
        : active
        ? (const Color(0xFF34C759), l10n.statusActive)
        : (Theme.of(context).colorScheme.onSurfaceVariant, l10n.statusStandby);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Right: detail editor ────────────────────────────────────────────────────

class _ServiceDetail extends StatefulWidget {
  final AiServiceProfile profile;
  final bool isActive;
  const _ServiceDetail({
    super.key,
    required this.profile,
    required this.isActive,
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
  late double _temperature;
  bool _obscureKey = true;

  bool _testing = false;
  bool? _testOk;

  /// What the last successful test found the server reporting. Shown beside
  /// the fields rather than written into them: a loaded size and a model
  /// maximum are different claims, and only the user knows which one the
  /// budget should follow.
  ModelLimits? _detected;

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
    _temperature = p.temperature;
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    _model.dispose();
    _contextWindow.dispose();
    _maxOutput.dispose();
    super.dispose();
  }

  AiConfig _config() => AiConfig(
    provider: _provider,
    endpoint: _endpoint.text.trim(),
    apiKey: _apiKey.text.trim(),
    model: _model.text.trim(),
    temperature: _temperature,
    contextWindow: AiConfig.tokenCount(_contextWindow.text),
    maxOutputTokens: AiConfig.tokenCount(_maxOutput.text),
  );

  void _persist() {
    final config = _config();
    final updated = AiServiceProfile(
      id: widget.profile.id,
      name: _name.text,
      provider: config.provider,
      endpoint: config.endpoint,
      apiKey: config.apiKey,
      model: config.model,
      temperature: config.temperature,
      contextWindow: config.contextWindow,
      maxOutputTokens: config.maxOutputTokens,
    );
    context.read<AiProfilesService>().update(updated);
    if (widget.isActive) {
      context.read<AiService>().updateConfig(config);
    }
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
      if (checked != null) _detected = checked.limits;
    });
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final badge = _badge(_provider);

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
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.aiServiceDetailHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
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
                      fontSize: 13,
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
                onChanged: (_) => _persist(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Token budget: the context the model is loaded with, and its cap.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Field(
                label: l10n.contextWindow,
                controller: _contextWindow,
                mono: true,
                digitsOnly: true,
                hint: l10n.contextWindowHint,
                onChanged: (_) => _persist(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Field(
                label: l10n.maxOutputTokens,
                controller: _maxOutput,
                mono: true,
                digitsOnly: true,
                hint: l10n.maxOutputTokensHint,
                onChanged: (_) => _persist(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_detected case final detected?)
          _DetectedLimits(
            limits: detected,
            onUse: () => _useDetected(detected),
          ),
        Text(
          l10n.contextWindowNote,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Temperature slider.
        _SliderField(
          label: l10n.temperature,
          value: _temperature.toStringAsFixed(1),
          slider: Slider(
            value: _temperature,
            max: 2,
            divisions: 20,
            onChanged: (v) => setState(() => _temperature = v),
            onChangeEnd: (_) => _persist(),
          ),
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
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: 12,
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
        fontSize: 12.5,
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

  const _Field({
    required this.label,
    required this.controller,
    this.mono = false,
    this.obscure = false,
    this.trailing,
    this.onChanged,
    this.hint,
    this.digitsOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  onChanged: onChanged,
                  keyboardType: digitsOnly ? TextInputType.number : null,
                  inputFormatters: digitsOnly
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : null,
                  style: TextStyle(
                    fontSize: 15,
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
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
          ),
          if (found)
            TextButton(onPressed: onUse, child: Text(l10n.useDetectedValue)),
        ],
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  final String label;
  final String value;
  final Widget slider;
  const _SliderField({
    required this.label,
    required this.value,
    required this.slider,
  });

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FieldLabel(label),
              const SizedBox(width: 8),
              Text(
                '· $value',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              overlayShape: SliderComponentShape.noOverlay,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
            ),
            child: slider,
          ),
        ],
      ),
    );
  }
}

class _ProtocolSegmented extends StatelessWidget {
  final AiProviderType value;
  final ValueChanged<AiProviderType> onChanged;
  const _ProtocolSegmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: glass.panelStroke),
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
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
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
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          colors: [Color(0xFF22C9A9), Color(0xFF2FA98A)],
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
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final ai = context.watch<AiService>();

    final tokens = active ? '${ai.totalTokens}' : '—';
    final reqs = active ? '${ai.requestCount}' : '—';
    final latency = active && ai.avgLatencyMs > 0
        ? '${ai.avgLatencyMs} ms'
        : '—';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glass.panelStroke),
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
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
                  borderRadius: BorderRadius.circular(3),
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
