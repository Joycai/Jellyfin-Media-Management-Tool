import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/platform_profiles.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';
import 'ai_settings_widgets.dart';

/// Asks for a platform, a key and a host, and returns the channel to add —
/// or null when cancelled. Nothing is saved here.
Future<AiChannel?> showAddChannelDialog(BuildContext context) =>
    showGlassDialog<AiChannel>(
      context: context,
      builder: (_) => const AddChannelDialog(),
    );

/// The routes a new channel on [platform] starts with: every protocol a
/// vendor or local server offers that this build can speak, primary first;
/// on a relay or a custom endpoint only the primary one — which of the
/// others exist there is the user's to say, on the channel page.
List<AiRoute> initialRoutes(PlatformProfile platform) {
  final inBuild = [
    for (final protocol in platform.routes.keys)
      if (protocolInBuild(protocol)) protocol,
  ];
  final all =
      platform.kind == PlatformKind.relay ||
          platform.kind == PlatformKind.custom
      ? inBuild.take(1)
      : inBuild;
  return [for (final protocol in all) AiRoute(protocol: protocol)];
}

class AddChannelDialog extends StatefulWidget {
  const AddChannelDialog({super.key});

  @override
  State<AddChannelDialog> createState() => _AddChannelDialogState();
}

class _AddChannelDialogState extends State<AddChannelDialog> {
  PlatformProfile _platform = PlatformProfiles.openAi;
  final _name = TextEditingController();
  final _host = TextEditingController(
    text: PlatformProfiles.openAi.defaultBaseUrl,
  );
  final _key = TextEditingController();
  bool _nameEdited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nameEdited) {
      _name.text = platformName(AppLocalizations.of(context)!, _platform);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _key.dispose();
    super.dispose();
  }

  void _pick(PlatformProfile platform) {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _platform = platform;
      _host.text = platform.defaultBaseUrl;
      if (!_nameEdited) _name.text = platformName(l10n, platform);
    });
  }

  bool get _complete =>
      _host.text.trim().isNotEmpty &&
      (!_platform.needsKey || _key.text.trim().isNotEmpty) &&
      initialRoutes(_platform).isNotEmpty;

  void _submit() {
    if (!_complete) return;
    final channel = AiChannel.create(
      platform: _platform,
      name: _name.text.trim().isEmpty
          ? platformName(AppLocalizations.of(context)!, _platform)
          : _name.text.trim(),
      baseUrl: _host.text.trim(),
      apiKey: _key.text.trim(),
    ).copyWith(routes: initialRoutes(_platform));
    Navigator.pop(context, channel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;

    Widget group(String label, PlatformKind kind) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.xxs,
          ),
          child: Text(
            label,
            style: AppTypeScale.columnHeader.copyWith(color: t.textMuted),
          ),
        ),
        for (final platform in PlatformProfiles.all)
          if (platform.kind == kind)
            _PlatformTile(
              platform: platform,
              selected: platform == _platform,
              onTap: () => _pick(platform),
            ),
      ],
    );

    return GlassAlertDialog(
      // The AddChannel artboard's dialog: a platform column beside the
      // preview, too wide for the 560 default.
      maxWidth: 760,
      title: Text(l10n.aiAddChannel),
      content: SizedBox(
        // AddChannel artboard: the dialog body is 460 tall, the platform
        // column 240 wide.
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.aiAddChannelHint),
            const SizedBox(height: AppSpacing.md12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 240,
                    child: ListView(
                      children: [
                        group(l10n.aiPlatformGroupVendor, PlatformKind.vendor),
                        group(l10n.aiPlatformGroupRelay, PlatformKind.relay),
                        group(l10n.aiPlatformGroupLocal, PlatformKind.local),
                        const SizedBox(height: AppSpacing.sm),
                        _PlatformTile(
                          platform: PlatformProfiles.custom,
                          label: l10n.aiPlatformCustomHint,
                          selected: _platform == PlatformProfiles.custom,
                          onTap: () => _pick(PlatformProfiles.custom),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: _preview(l10n, t)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppButton.primary(
          label: l10n.aiAddChannel,
          onPressed: _complete ? _submit : null,
        ),
      ],
    );
  }

  Widget _preview(AppLocalizations l10n, AppTokens t) {
    final routes = initialRoutes(_platform);
    return ListView(
      children: [
        Text(
          l10n.aiWillCreate(platformName(l10n, _platform)),
          style: AppTypeScale.controlStrong.copyWith(color: t.textTitle),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in _platform.routes.entries)
          _RoutePreview(
            protocol: entry.key,
            spec: entry.value,
            primary: routes.firstOrNull?.protocol == entry.key,
            created: routes.any((r) => r.protocol == entry.key),
          ),
        const SizedBox(height: AppSpacing.md12),
        AiField(
          label: l10n.aiChannelKey,
          controller: _key,
          mono: true,
          obscure: true,
          hint: _platform.needsKey ? null : l10n.apiKeyOptionalHint,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        AiField(
          label: l10n.aiChannelHost,
          controller: _host,
          mono: true,
          hint: 'https://',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        AiField(
          label: l10n.aiChannelName,
          controller: _name,
          onChanged: (_) => _nameEdited = true,
        ),
      ],
    );
  }
}

class _PlatformTile extends StatelessWidget {
  final PlatformProfile platform;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  const _PlatformTile({
    required this.platform,
    this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return AppListRow(
      selected: selected,
      onTap: onTap,
      height: label == null ? AppSizes.row : AppSizes.rowTall,
      child: Row(
        children: [
          AiBadge(platform: platform, size: AppSizes.controlXs - 2),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label ?? platformName(l10n, platform),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.control.copyWith(color: t.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePreview extends StatelessWidget {
  final AiProviderType protocol;
  final RouteSpec spec;
  final bool primary;
  final bool created;

  const _RoutePreview({
    required this.protocol,
    required this.spec,
    required this.primary,
    required this.created,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final inBuild = protocolInBuild(protocol);
    final dialect = spec.thinkingDialect;
    final line = [
      spec.defaultPath.isEmpty ? l10n.aiRouteHostItself : spec.defaultPath,
      if (!inBuild)
        l10n.aiRouteNotInBuild
      else if (dialect != null)
        l10n.aiRouteDialect(dialect.field(thinking: false).key),
    ].join(' · ');
    return Opacity(
      opacity: created ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            ProtocolChip(
              protocol: protocol,
              state: created
                  ? (primary
                        ? ProtocolChipState.current
                        : ProtocolChipState.enabled)
                  : ProtocolChipState.offered,
            ),
            if (primary) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.aiPrimaryRoute,
                style: AppTypeScale.caption.copyWith(color: t.accent),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.monoTiny.copyWith(color: t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
