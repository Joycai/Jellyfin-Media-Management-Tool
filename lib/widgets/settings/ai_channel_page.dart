import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_profiles_service.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/platform_profiles.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';
import 'ai_diagnostics_page.dart';
import 'ai_services_screen.dart';
import 'ai_settings_widgets.dart';

/// One channel: its name, host and key, the route table, and its models
/// (ChannelEdit artboard).
///
/// Every field saves as it is typed, like the rest of Settings.
class AiChannelPage extends StatefulWidget {
  final String channelId;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenModel;

  const AiChannelPage({
    super.key,
    required this.channelId,
    required this.onBack,
    required this.onOpenModel,
  });

  @override
  State<AiChannelPage> createState() => _AiChannelPageState();
}

class _AiChannelPageState extends State<AiChannelPage> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _key;
  final _newModel = TextEditingController();
  final Map<AiProviderType, TextEditingController> _paths = {};
  bool _obscureKey = true;

  /// The channel as it was before the current run of host edits. Every
  /// keystroke moves the routes from here, never from the half-typed host
  /// the previous keystroke left — `https://` alone would otherwise match
  /// every route on any host. A route edit starts a new run.
  AiChannel? _hostEditFrom;

  AiChannel get _channel =>
      context.read<AiProfilesService>().channelById(widget.channelId)!;

  @override
  void initState() {
    super.initState();
    final channel = context.read<AiProfilesService>().channelById(
      widget.channelId,
    )!;
    _name = TextEditingController(text: channel.name);
    _host = TextEditingController(text: channel.baseUrl);
    _key = TextEditingController(text: channel.apiKey);
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _key.dispose();
    _newModel.dispose();
    for (final controller in _paths.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _pathFor(AiChannel channel, AiProviderType protocol) =>
      _paths.putIfAbsent(
        protocol,
        () => TextEditingController(
          text: channel.routeFor(protocol)?.endpoint ?? '',
        ),
      );

  Future<void> _save(AiChannel Function(AiChannel) change) =>
      context.read<AiProfilesService>().updateChannel(change(_channel));

  Future<void> _saveRoutes(AiChannel Function(AiChannel) change) {
    _hostEditFrom = null;
    return _save(change);
  }

  Future<void> _setHost(String value) {
    final moved = (_hostEditFrom ??= _channel).withBaseUrl(value);
    return _save(
      (c) => c.copyWith(
        baseUrl: value,
        routes: [
          for (final route in c.routes) moved.routeFor(route.protocol) ?? route,
        ],
      ),
    );
  }

  Future<void> _setRoute(AiProviderType protocol, String path) => _saveRoutes(
    (c) => c.copyWith(
      routes: [
        for (final route in c.routes)
          route.protocol == protocol ? route.withEndpoint(path) : route,
      ],
    ),
  );

  Future<void> _enable(AiProviderType protocol) => _saveRoutes(
    (c) => c.copyWith(
      routes: [
        ...c.routes,
        AiRoute(protocol: protocol).withEndpoint(_paths[protocol]?.text),
      ],
    ),
  );

  Future<void> _disable(AiProviderType protocol) => _saveRoutes(
    (c) => c.copyWith(
      routes: c.routes.where((r) => r.protocol != protocol).toList(),
    ),
  );

  Future<void> _makePrimary(AiProviderType protocol) => _saveRoutes((c) {
    final route = c.routeFor(protocol)!;
    return c.copyWith(
      routes: [route, ...c.routes.where((r) => r.protocol != protocol)],
    );
  });

  Future<void> _addModel() async {
    final name = _newModel.text.trim();
    final channel = _channel;
    final primary = channel.primaryProtocol;
    if (name.isEmpty || primary == null) return;
    final model = AiModelEntry.create(upstream: name, route: primary);
    await context.read<AiProfilesService>().upsertModel(channel.id, model);
    _newModel.clear();
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final channel = _channel;
    final profiles = context.read<AiProfilesService>();
    final confirm = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: Text(l10n.aiDeleteChannel),
        content: Text(
          l10n.aiDeleteChannelConfirm(channel.name, channel.models.length),
        ),
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
    await profiles.deleteChannel(channel.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final channel = context.watch<AiProfilesService>().channelById(
      widget.channelId,
    )!;
    final platform = channel.platform;
    final inferred = channel.platformId == null;

    // Offered by the platform, plus any route the channel has that its
    // platform does not list (a migrated custom endpoint).
    final protocols = {
      ...platform.routes.keys,
      for (final route in channel.routes) route.protocol,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiPageHeader(
          backLabel: l10n.aiAccessTitle,
          onBack: widget.onBack,
          title: channel.name,
          subtitle: inferred
              ? l10n.aiPlatformInferred(platformName(l10n, platform))
              : l10n.aiPlatformChosen(platformName(l10n, platform)),
          actions: [
            AppButton(
              label: l10n.aiDeleteChannel,
              icon: Icons.delete_outline,
              kind: AppButtonKind.danger,
              onPressed: _delete,
            ),
          ],
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AiField(
                      label: l10n.aiChannelName,
                      controller: _name,
                      onChanged: (v) => _save((c) => c.copyWith(name: v)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: _PlatformPicker(
                      channel: channel,
                      onChanged: (id) =>
                          _save((c) => c.copyWith(platformId: () => id)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AiField(
                      label:
                          '${l10n.aiChannelHost} · ${l10n.aiChannelHostHint}',
                      controller: _host,
                      mono: true,
                      onChanged: (v) async {
                        await _setHost(v);
                        // Routes built on the old host moved with it; their
                        // fields must show where they point now.
                        final moved = _channel;
                        for (final MapEntry(key: protocol, value: field)
                            in _paths.entries) {
                          field.text = moved.routeFor(protocol)?.endpoint ?? '';
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: AiField(
                      label: l10n.aiChannelKey,
                      controller: _key,
                      mono: true,
                      obscure: _obscureKey,
                      hint: platform.needsKey ? null : l10n.apiKeyOptionalHint,
                      onChanged: (v) => _save((c) => c.copyWith(apiKey: v)),
                      trailing: AppButton.ghost(
                        label: _obscureKey ? l10n.showKey : l10n.hideKey,
                        height: AppSizes.controlXs,
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AiCard(
                title: l10n.aiRoutesTitle,
                note: l10n.aiRoutesHint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final protocol in protocols) ...[
                      _RouteRow(
                        key: ValueKey(protocol),
                        channel: channel,
                        protocol: protocol,
                        path: _pathFor(channel, protocol),
                        onPath: (v) => _setRoute(protocol, v),
                        onEnable: () => _enable(protocol),
                        onDisable: () => _disable(protocol),
                        onMakePrimary: () => _makePrimary(protocol),
                      ),
                      Divider(height: AppSpacing.lg, color: t.stroke),
                    ],
                    Text(
                      l10n.aiRoutePathNote,
                      style: AppTypeScale.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AiCard(
                title: l10n.aiModelsTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final model in channel.models)
                      AppListRow(
                        onTap: () => widget.onOpenModel(model.id),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.upstream,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.monoBody.copyWith(color: t.textBody),
                              ),
                            ),
                            ProtocolChip(
                              protocol: channel.configFor(model).provider,
                              state: ProtocolChipState.current,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: t.textMuted,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _newModel,
                            hint: l10n.aiModelNameHint,
                            mono: true,
                            onSubmitted: (_) => _addModel(),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AppButton(
                          label: l10n.aiAddModel,
                          icon: Icons.add,
                          onPressed: channel.routes.isEmpty ? null : _addModel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlatformPicker extends StatelessWidget {
  final AiChannel channel;
  final ValueChanged<String?> onChanged;

  const _PlatformPicker({required this.channel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final inferred = PlatformProfiles.forHost(channel.baseUrl);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md12,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: t.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: t.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiFieldLabel(l10n.aiPlatformLabel),
          DropdownButton<String?>(
            // The theme's canvas is transparent for the glass backdrop; the
            // menu needs the same opaque fill as every other popup.
            dropdownColor: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.field),
            value: channel.platformId,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(
                  l10n.aiPlatformInferred(
                    platformName(l10n, inferred ?? PlatformProfiles.custom),
                  ),
                  style: AppTypeScale.control.copyWith(color: t.textBody),
                ),
              ),
              for (final platform in PlatformProfiles.all)
                DropdownMenuItem(
                  value: platform.id,
                  child: Text(
                    platformName(l10n, platform),
                    style: AppTypeScale.control.copyWith(color: t.textBody),
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatefulWidget {
  final AiChannel channel;
  final AiProviderType protocol;
  final TextEditingController path;
  final ValueChanged<String> onPath;
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onMakePrimary;

  const _RouteRow({
    super.key,
    required this.channel,
    required this.protocol,
    required this.path,
    required this.onPath,
    required this.onEnable,
    required this.onDisable,
    required this.onMakePrimary,
  });

  @override
  State<_RouteRow> createState() => _RouteRowState();
}

class _RouteRowState extends State<_RouteRow> {
  bool _testing = false;
  String? _result;
  bool _ok = false;

  /// Tests the route with the first model on it: a route alone has nothing
  /// to generate with.
  Future<void> _test(ChannelModel entry) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _testing = true;
      _result = null;
    });
    final outcome = await runRouteTest(context, entry);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = outcome.result != null;
      _result = outcome.result != null
          ? describeCheck(l10n, outcome.result!)
          : l10n.connectionFailed(outcome.error ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final channel = widget.channel;
    final protocol = widget.protocol;
    final route = channel.routeFor(protocol);
    final enabled = route != null;
    final primary = channel.primaryProtocol == protocol;
    final inBuild = protocolInBuild(protocol);
    final users = [
      for (final m in channel.models)
        if (channel.configFor(m).provider == protocol) m,
    ];
    final spec = channel.platform.routes[protocol];
    final defaultPath = spec == null
        ? l10n.aiRouteHostItself
        : (spec.defaultPath.isEmpty
              ? l10n.aiRouteHostItself
              : spec.defaultPath);
    final dialect = spec?.thinkingDialect;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProtocolChip(
              protocol: protocol,
              state: !enabled
                  ? ProtocolChipState.offered
                  : primary
                  ? ProtocolChipState.current
                  : ProtocolChipState.enabled,
            ),
            if (primary) ...[
              const SizedBox(width: AppSpacing.xs),
              AiStatusChip(label: l10n.aiPrimaryRoute, color: t.accent),
            ],
            if (enabled && channel.hasOwnHost(protocol)) ...[
              const SizedBox(width: AppSpacing.xs),
              AiStatusChip(label: l10n.aiRouteOwnHost, color: t.warning),
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                dialect != null
                    ? l10n.aiRouteDialect(dialect.field(thinking: false).key)
                    : '',
                style: AppTypeScale.caption.copyWith(color: t.textMuted),
              ),
            ),
            if (!inBuild)
              AiStatusChip(label: l10n.aiRouteNotInBuild, color: t.textMuted)
            else if (!enabled)
              AppButton(
                label: l10n.aiRouteEnable,
                height: AppSizes.controlSm,
                onPressed: widget.onEnable,
              )
            else ...[
              if (users.isNotEmpty)
                AppButton(
                  label: l10n.aiTestRoute,
                  height: AppSizes.controlSm,
                  onPressed: _testing
                      ? null
                      : () => _test((channel: channel, model: users.first)),
                ),
              if (!primary) ...[
                const SizedBox(width: AppSpacing.xs),
                AppButton.ghost(
                  label: l10n.aiRouteMakePrimary,
                  height: AppSizes.controlSm,
                  onPressed: widget.onMakePrimary,
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              AppButton.ghost(
                label: l10n.aiRouteDisable,
                height: AppSizes.controlSm,
                // A route a model runs on cannot go away under it.
                onPressed: users.isEmpty && channel.routes.length > 1
                    ? widget.onDisable
                    : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (enabled) ...[
          AppTextField(
            controller: widget.path,
            mono: true,
            hint: l10n.aiRoutePathDefault(defaultPath),
            onChanged: widget.onPath,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'POST ${channel.endpointFor(protocol)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.monoTiny.copyWith(color: t.textMuted),
          ),
          if (users.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.aiRouteInUse(users.length),
              style: AppTypeScale.caption.copyWith(color: t.textMuted),
            ),
          ],
          if (_testing || _result != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _testing ? '…' : _result!,
              style: AppTypeScale.caption.copyWith(
                color: _testing ? t.textMuted : (_ok ? t.success : t.danger),
              ),
            ),
          ],
        ] else if (inBuild)
          Text(
            l10n.aiRouteNotEnabled,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
      ],
    );
  }
}
