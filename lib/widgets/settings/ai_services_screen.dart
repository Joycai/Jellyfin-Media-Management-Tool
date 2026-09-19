import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_profiles_service.dart';
import '../../services/ai/ai_service.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../glass/glass_dialog.dart';
import '../ui/app_controls.dart';
import 'ai_add_channel_dialog.dart';
import 'ai_capability_matrix.dart';
import 'ai_channel_page.dart';
import 'ai_diagnostics_page.dart';
import 'ai_model_page.dart';
import 'ai_settings_widgets.dart';
import 'settings_controls.dart';

/// Settings → AI access (design canvas "AI 接入配置重设计").
///
/// Channels, their routes and models, and which model each task runs on.
/// One pane with its own small navigation — overview, a channel, a model,
/// its capability matrix, diagnostics — because every page here is a drill
/// down from the one before and the settings sidebar should stay put.
class AiServicesView extends StatefulWidget {
  const AiServicesView({super.key});

  @override
  State<AiServicesView> createState() => _AiServicesViewState();
}

sealed class _Page {
  const _Page();
}

class _Overview extends _Page {
  const _Overview();
}

class _Channel extends _Page {
  final String channelId;
  const _Channel(this.channelId);
}

class _Model extends _Page {
  final String channelId;
  final String modelId;
  const _Model(this.channelId, this.modelId);
}

class _Matrix extends _Page {
  final String channelId;
  final String modelId;
  const _Matrix(this.channelId, this.modelId);
}

class _Diagnostics extends _Page {
  final String? modelId;
  const _Diagnostics(this.modelId);
}

class _AiServicesViewState extends State<AiServicesView> {
  _Page _page = const _Overview();

  void _go(_Page page) => setState(() => _page = page);

  Future<void> _addChannel() async {
    final channel = await showAddChannelDialog(context);
    if (channel == null || !mounted) return;
    await context.read<AiProfilesService>().addChannel(channel);
    _go(_Channel(channel.id));
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<AiProfilesService>();
    // A page whose channel or model was deleted falls back to the overview.
    return switch (_page) {
      _Channel(:final channelId) when profiles.channelById(channelId) != null =>
        AiChannelPage(
          channelId: channelId,
          onBack: () => _go(const _Overview()),
          onOpenModel: (id) => _go(_Model(channelId, id)),
        ),
      _Model(:final channelId, :final modelId)
          when profiles.modelById(modelId) != null =>
        AiModelPage(
          channelId: channelId,
          modelId: modelId,
          onBack: () => _go(_Channel(channelId)),
          onMatrix: () => _go(_Matrix(channelId, modelId)),
          onDiagnostics: () => _go(_Diagnostics(modelId)),
        ),
      _Matrix(:final channelId, :final modelId)
          when profiles.modelById(modelId) != null =>
        AiCapabilityMatrixPage(
          channelId: channelId,
          modelId: modelId,
          onBack: () => _go(_Model(channelId, modelId)),
        ),
      _Diagnostics(:final modelId) => AiDiagnosticsPage(
        initialModelId: modelId,
        onBack: () => _go(const _Overview()),
      ),
      _ => _OverviewPage(
        onAddChannel: _addChannel,
        onOpenChannel: (id) => _go(_Channel(id)),
        onOpenModel: (channelId, modelId) => _go(_Model(channelId, modelId)),
        onDiagnostics: () => _go(const _Diagnostics(null)),
      ),
    };
  }
}

class _OverviewPage extends StatelessWidget {
  final VoidCallback onAddChannel;
  final ValueChanged<String> onOpenChannel;
  final void Function(String channelId, String modelId) onOpenModel;
  final VoidCallback onDiagnostics;

  const _OverviewPage({
    required this.onAddChannel,
    required this.onOpenChannel,
    required this.onOpenModel,
    required this.onDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final profiles = context.watch<AiProfilesService>();
    final channels = profiles.channels;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl24,
        AppSpacing.lg,
        AppSpacing.xl24,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aiAccessTitle,
                      style: AppTypeScale.title.copyWith(color: t.textTitle),
                    ),
                    const SizedBox(height: AppSpacing.xxs / 2),
                    Text(
                      l10n.aiAccessSubtitle,
                      style: AppTypeScale.caption.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: l10n.aiDiagnostics,
                icon: Icons.monitor_heart_outlined,
                onPressed: onDiagnostics,
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton.primary(
                label: l10n.aiAddChannel,
                icon: Icons.add,
                onPressed: onAddChannel,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
          for (final group in profiles.mergeCandidates) ...[
            _MergeBanner(group: group),
            const SizedBox(height: AppSpacing.md12),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: channels.isEmpty
                      ? _EmptyState(onAdd: onAddChannel)
                      : ListView.separated(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.xl24,
                          ),
                          itemCount: channels.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.md12),
                          itemBuilder: (_, i) => _ChannelCard(
                            channel: channels[i],
                            onOpen: () => onOpenChannel(channels[i].id),
                            onOpenModel: (id) =>
                                onOpenModel(channels[i].id, id),
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  // The design's task column (Main.dc.html, 320 of 1180).
                  width: 320,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl24),
                    children: const [
                      _TasksCard(),
                      SizedBox(height: AppSpacing.md12),
                      _UsageCard(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MergeBanner extends StatelessWidget {
  final List<AiChannel> group;
  const _MergeBanner({required this.group});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final routes = {
      for (final channel in group)
        for (final route in channel.routes) route.protocol,
    };
    final models = group.fold(0, (sum, c) => sum + c.models.length);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md12,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.aiSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: t.ai.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.merge_type, size: 16, color: t.ai),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.aiMergeHint(
                group.map((c) => c.name).join(' · '),
                routes.length,
                models,
              ),
              style: AppTypeScale.caption.copyWith(color: t.textBody),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: l10n.aiMergeAction,
            height: AppSizes.controlSm,
            onPressed: () => _confirm(context),
          ),
        ],
      ),
    );
  }
}

extension on _MergeBanner {
  /// Merging cannot be undone and drops every name but the first, so it
  /// asks once.
  Future<void> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final profiles = context.read<AiProfilesService>();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: Text(l10n.aiMergeConfirmTitle),
        content: Text(l10n.aiMergeConfirmBody(group.first.name)),
        actions: [
          AppButton(
            label: l10n.cancel,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppButton.primary(
            label: l10n.aiMergeAction,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (ok == true) await profiles.merge([for (final c in group) c.id]);
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 48, color: t.textMuted),
          const SizedBox(height: AppSpacing.md12),
          Text(
            l10n.aiEmptyTitle,
            style: AppTypeScale.bodyStrong.copyWith(color: t.textTitle),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.aiEmptyBody,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.primary(
            label: l10n.aiAddChannel,
            icon: Icons.add,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// The host a channel is shown by: host and port, no scheme or path.
String channelHost(AiChannel channel) {
  final uri = Uri.tryParse(channel.baseUrl.trim());
  if (uri == null || uri.host.isEmpty) return channel.baseUrl;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

class _ChannelCard extends StatelessWidget {
  final AiChannel channel;
  final VoidCallback onOpen;
  final ValueChanged<String> onOpenModel;

  const _ChannelCard({
    required this.channel,
    required this.onOpen,
    required this.onOpenModel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final platform = channel.platform;
    final needsKey = platform.needsKey || channel.apiKey.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: t.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: t.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.panel),
            ),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md12),
              child: Row(
                children: [
                  AiBadge(platform: platform, size: AppSizes.control),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypeScale.bodyStrong.copyWith(
                            color: t.textTitle,
                          ),
                        ),
                        Text(
                          needsKey
                              ? l10n.aiChannelHostLine(
                                  channelHost(channel),
                                  platformName(l10n, platform),
                                )
                              : '${channelHost(channel)} · ${l10n.aiNoKeyNeeded}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.monoTiny.copyWith(color: t.textMuted),
                        ),
                      ],
                    ),
                  ),
                  // A single-route channel shows no route UI at all: it looks
                  // and behaves exactly like a profile did.
                  if (channel.routes.length > 1)
                    for (final route in channel.routes) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      ProtocolChip(protocol: route.protocol, short: true),
                    ],
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.chevron_right, size: 18, color: t.textMuted),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: t.stroke),
          if (channel.models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md12),
              child: Text(
                l10n.aiNoModels,
                style: AppTypeScale.caption.copyWith(color: t.textMuted),
              ),
            )
          else
            for (final model in channel.models)
              _ModelRow(
                channel: channel,
                model: model,
                onTap: () => onOpenModel(model.id),
              ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final AiChannel channel;
  final AiModelEntry model;
  final VoidCallback onTap;

  const _ModelRow({
    required this.channel,
    required this.model,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final config = channel.configFor(model);
    final tools = config.supportsTools;
    return AppListRow(
      height: AppSizes.rowTall,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              model.upstream.isEmpty ? '—' : model.upstream,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.monoBody.copyWith(color: t.textBody),
            ),
          ),
          if (model.imageInput) ...[
            AiStatusChip(label: l10n.aiImage, color: t.ai),
            const SizedBox(width: AppSpacing.xxs),
          ],
          if (model.videoInput) ...[
            AiStatusChip(label: l10n.aiVideo, color: t.ai),
            const SizedBox(width: AppSpacing.xxs),
          ],
          switch (tools) {
            true => AiStatusChip(label: l10n.aiToolsYes, color: t.success),
            false => AiStatusChip(label: l10n.aiToolsNo, color: t.danger),
            null => AiStatusChip(label: l10n.aiToolsUnprobed, color: t.warning),
          },
          if (channel.routes.length > 1) ...[
            const SizedBox(width: AppSpacing.sm),
            ProtocolChip(
              protocol: config.provider,
              state: ProtocolChipState.current,
            ),
          ],
        ],
      ),
    );
  }
}

/// Which model each task runs on.
class _TasksCard extends StatelessWidget {
  const _TasksCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final profiles = context.watch<AiProfilesService>();
    final settings = context.watch<SettingsService>();
    return AiCard(
      title: l10n.aiTasksTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiTasksHint,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
          for (final task in AiTask.values) ...[
            const SizedBox(height: AppSpacing.md12),
            AiFieldLabel(switch (task) {
              AiTask.organize => l10n.aiTaskOrganize,
              AiTask.scrapeLearn => l10n.aiTaskScrapeLearn,
              AiTask.scrapeDirect => l10n.aiTaskScrapeDirect,
              AiTask.vision => l10n.aiTaskVision,
            }),
            const SizedBox(height: AppSpacing.xs),
            _TaskPicker(task: task, profiles: profiles),
            if (task == AiTask.vision) ...[
              const SizedBox(height: AppSpacing.xs),
              // Consent is for the model shown above: pick another and this
              // reads off until the user allows that one too. Nothing to
              // consent to without a model allowed images.
              if (profiles.visionConfig case final vision)
                SettingsToggleRow(
                  label: l10n.aiVisionAllowFrames,
                  subtitle: l10n.aiVisionAllowFramesHint,
                  value:
                      vision != null && settings.visionFramesAllowedFor(vision),
                  onChanged: vision == null
                      ? null
                      : (on) => settings.setVisionFramesFor(on ? vision : null),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Whether [entry] may run [task]: its route has an adapter in this build,
/// a tool-loop task needs a model not known to lack tools, and frame
/// recognition needs image input allowed.
bool taskAccepts(AiTask task, ChannelModel entry) {
  final config = entry.channel.configFor(entry.model);
  if (!protocolInBuild(config.provider)) return false;
  if (task == AiTask.vision) return entry.model.imageInput;
  return config.supportsTools != false;
}

class _TaskPicker extends StatelessWidget {
  final AiTask task;
  final AiProfilesService profiles;

  const _TaskPicker({required this.task, required this.profiles});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final eligible = [
      for (final entry in profiles.allModels)
        if (taskAccepts(task, entry)) entry,
    ];
    final assigned = profiles.tasks[task];
    // An assignment that no longer qualifies is still shown, so the picker
    // never silently claims a different model than the one that will run.
    final current = profiles.modelById(assigned);
    final items = <DropdownMenuItem<String?>>[
      if (task != AiTask.organize)
        DropdownMenuItem(
          value: null,
          child: Text(
            l10n.aiFollowOrganize,
            style: AppTypeScale.control.copyWith(color: t.textMuted),
          ),
        ),
      for (final entry in [
        ...eligible,
        if (current != null && !eligible.contains(current)) current,
      ])
        DropdownMenuItem(
          value: entry.model.id,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  entry.model.upstream,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.monoSmall.copyWith(color: t.textBody),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  '${entry.channel.name} · '
                  '${protocolShortName(entry.channel.configFor(entry.model).provider)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.caption.copyWith(color: t.textMuted),
                ),
              ),
            ],
          ),
        ),
    ];
    final value = task == AiTask.organize
        ? profiles.resolve(AiTask.organize)?.model.id
        : (current == null ? null : assigned);
    final empty = task == AiTask.organize ? items.isEmpty : eligible.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: value,
          key: ValueKey('${task.id}|$value|${items.length}'),
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(AppRadii.field),
          items: items,
          onChanged: items.isEmpty ? null : (id) => profiles.assign(task, id),
        ),
        if (empty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            task == AiTask.vision
                ? l10n.aiVisionNeedsImage
                : l10n.aiTaskNoModel,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
        ],
      ],
    );
  }
}

/// This launch's usage, as [AiService] counts it.
class _UsageCard extends StatelessWidget {
  const _UsageCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final ai = context.watch<AiService>();

    Widget stat(String label, String value) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
        ),
        Text(value, style: t.monoSmall.copyWith(color: t.textBody)),
      ],
    );

    return AiCard(
      title: l10n.aiSessionUsage,
      child: Column(
        children: [
          stat(l10n.requests, '${ai.requestCount}'),
          const SizedBox(height: AppSpacing.xs),
          stat(l10n.tokensThisSession, '${ai.totalTokens}'),
          const SizedBox(height: AppSpacing.xs),
          stat(
            l10n.avgLatency,
            ai.avgLatencyMs > 0 ? '${ai.avgLatencyMs} ms' : '—',
          ),
        ],
      ),
    );
  }
}

/// Shared header for the drill-down pages: a back button naming where it
/// goes, the page title, and actions on the right.
class AiPageHeader extends StatelessWidget {
  final String backLabel;
  final VoidCallback onBack;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const AiPageHeader({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl24,
        AppSpacing.lg,
        AppSpacing.xl24,
        AppSpacing.md12,
      ),
      child: Row(
        children: [
          AppButton(
            label: backLabel,
            icon: Icons.chevron_left,
            height: AppSizes.controlSm,
            onPressed: onBack,
          ),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.title.copyWith(color: t.textTitle),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypeScale.caption.copyWith(color: t.textMuted),
                  ),
              ],
            ),
          ),
          for (final action in actions) ...[
            const SizedBox(width: AppSpacing.sm),
            action,
          ],
        ],
      ),
    );
  }
}
