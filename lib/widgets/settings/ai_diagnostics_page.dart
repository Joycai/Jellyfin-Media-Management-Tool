import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_channel.dart';
import '../../services/ai/ai_http.dart';
import '../../services/ai/ai_profiles_service.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/api_log.dart';
import '../../services/ai/connection_check.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import 'ai_services_screen.dart';
import 'ai_settings_widgets.dart';

/// Runs the connection test for [entry] on its current route, and records
/// what it settled about tool calling on every model that shares the route.
/// A probe that never completed is not an answer and records nothing.
Future<({AiConnectionCheckResult? result, String? error})> runRouteTest(
  BuildContext context,
  ChannelModel entry,
) async {
  final ai = context.read<AiService>();
  final profiles = context.read<AiProfilesService>();
  final config = entry.channel.configFor(entry.model);
  if (!config.isComplete) {
    return (
      result: null,
      error: AppLocalizations.of(context)!.connectionIncomplete,
    );
  }
  try {
    final result = await ai.testConnection(config);
    if (result.supportsTools != ToolProbe.inconclusive) {
      profiles.recordToolSupport(
        config,
        result.supportsTools == ToolProbe.supported,
      );
      ai.updateConfig(profiles.aiConfig);
    }
    return (result: result, error: null);
  } catch (e) {
    return (result: null, error: AiHttp.describeFailure(e));
  }
}

/// One line for a snackbar or a route row.
String describeCheck(AppLocalizations l10n, AiConnectionCheckResult result) {
  var reply = result.reply.replaceAll(RegExp(r'\s+'), ' ');
  if (reply.length > 120) reply = '${reply.substring(0, 120)}…';
  final text = l10n.connectionOkReply(
    result.latency.inMilliseconds,
    reply.isEmpty ? l10n.connectionEmptyReply : reply,
  );
  return result.truncated ? '$text\n${l10n.connectionTruncated}' : text;
}

/// Diagnostics (Diagnostics artboard): test one route step by step, and read
/// today's API log.
class AiDiagnosticsPage extends StatefulWidget {
  final String? initialModelId;
  final VoidCallback onBack;

  const AiDiagnosticsPage({
    super.key,
    required this.initialModelId,
    required this.onBack,
  });

  @override
  State<AiDiagnosticsPage> createState() => _AiDiagnosticsPageState();
}

class _AiDiagnosticsPageState extends State<AiDiagnosticsPage> {
  String? _modelId;
  bool _testing = false;
  AiConnectionCheckResult? _result;
  String? _error;
  List<Map<String, dynamic>> _entries = const [];

  /// The expanded entry, by its sequence number: rows move as new entries
  /// arrive at the top.
  Object? _expanded;

  @override
  void initState() {
    super.initState();
    final profiles = context.read<AiProfilesService>();
    _modelId =
        profiles.modelById(widget.initialModelId)?.model.id ??
        profiles.resolve(AiTask.organize)?.model.id;
    _loadLog();
  }

  Future<void> _loadLog() async {
    await ApiLog.instance.flush();
    final file = ApiLog.instance.currentFile;
    var entries = <Map<String, dynamic>>[];
    try {
      if (file != null && await file.exists()) {
        final lines = await file.readAsLines();
        entries = [for (final line in lines.reversed.take(200)) ?_decode(line)];
      }
    } on FileSystemException {
      // A log that cannot be read shows as empty.
    }
    if (mounted) setState(() => _entries = entries);
  }

  static Map<String, dynamic>? _decode(String line) {
    try {
      final value = jsonDecode(line);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _run() async {
    final entry = context.read<AiProfilesService>().modelById(_modelId);
    if (entry == null) return;
    setState(() {
      _testing = true;
      _result = null;
      _error = null;
    });
    final outcome = await runRouteTest(context, entry);
    if (!mounted) return;
    setState(() {
      _testing = false;
      // Shown only under the model it was measured on.
      if (_modelId == entry.model.id) {
        _result = outcome.result;
        _error = outcome.error;
      }
    });
    await _loadLog();
  }

  Future<void> _useServed(int tokens) async {
    final profiles = context.read<AiProfilesService>();
    final entry = profiles.modelById(_modelId);
    if (entry == null) return;
    await profiles.upsertModel(
      entry.channel.id,
      entry.model.copyWith(contextWindow: () => tokens),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final profiles = context.watch<AiProfilesService>();
    final settings = context.watch<SettingsService>();
    final models = profiles.allModels;
    final entry = profiles.modelById(_modelId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiPageHeader(
          backLabel: l10n.aiAccessTitle,
          onBack: widget.onBack,
          title: l10n.aiDiagnostics,
          actions: [
            Text(
              l10n.privacyLogAiBodies,
              style: AppTypeScale.control.copyWith(color: t.textBody),
            ),
            AppToggle(
              value: settings.apiLogEnabled,
              onChanged: (v) async {
                await settings.setApiLogEnabled(v);
                await _loadLog();
              },
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl24,
              0,
              AppSpacing.xl24,
              AppSpacing.xl24,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  // Diagnostics artboard: the test column is 430 of 1180.
                  width: 430,
                  child: AiCard(
                    title: l10n.aiDiagTest,
                    fill: true,
                    child: ListView(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: entry?.model.id,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            for (final m in models)
                              DropdownMenuItem(
                                value: m.model.id,
                                child: Text(
                                  '${m.model.upstream} · ${m.channel.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.monoSmall.copyWith(
                                    color: t.textBody,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: _testing
                              ? null
                              : (id) => setState(() {
                                  _modelId = id;
                                  _result = null;
                                  _error = null;
                                }),
                        ),
                        if (entry != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${protocolName(entry.channel.configFor(entry.model).provider)}'
                            ' · ${entry.channel.endpointFor(entry.channel.configFor(entry.model).provider)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.monoTiny.copyWith(color: t.textMuted),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md12),
                        AppButton.primary(
                          label: l10n.aiDiagRun,
                          icon: Icons.play_arrow_rounded,
                          onPressed: entry == null || _testing ? null : _run,
                        ),
                        const SizedBox(height: AppSpacing.md12),
                        if (_testing) const LinearProgressIndicator(),
                        if (_error case final error?)
                          _Step(ok: false, text: l10n.connectionFailed(error)),
                        if ((_result, entry) case (final result?, final e?))
                          ..._steps(l10n, result, e),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: _logCard(l10n, t, settings.apiLogEnabled)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _steps(
    AppLocalizations l10n,
    AiConnectionCheckResult result,
    ChannelModel entry,
  ) {
    final config = entry.channel.configFor(entry.model);
    final served = result.limits.isModelMaximum
        ? null
        : result.limits.contextWindow;
    final typed = config.contextWindow;
    return [
      _Step(
        ok: true,
        text: result.serverKind == ServerKind.unknown
            ? l10n.aiStepReach
            : '${l10n.aiStepReach} · '
                  '${l10n.aiStepServer(_serverName(result.serverKind))}',
      ),
      _Step(
        ok: true,
        text: l10n.aiStepGenerate(
          result.latency.inMilliseconds,
          result.promptTokens,
          result.completionTokens,
        ),
      ),
      if (result.truncated) _Step(ok: false, text: l10n.aiStepTruncated),
      if (!config.thinkingEnabled)
        _Step(
          ok: !result.reasoned,
          text: result.reasoned
              ? l10n.aiStepThinkingStillOn
              : l10n.aiStepThinkingOff,
        ),
      switch (result.supportsTools) {
        ToolProbe.supported => _Step(ok: true, text: l10n.aiStepTools),
        ToolProbe.unsupported => _Step(ok: false, text: l10n.aiStepToolsNo),
        ToolProbe.inconclusive => _Step(
          ok: null,
          text: l10n.aiStepToolsUnknown,
        ),
      },
      _Step(
        ok: result.promptTokens + result.completionTokens > 0 ? true : null,
        text: result.promptTokens + result.completionTokens > 0
            ? l10n.aiStepUsage
            : l10n.aiStepUsageMissing,
      ),
      if (served != null && typed != null && typed > served)
        _ContextWarning(
          served: served,
          typed: typed,
          onUse: () => _useServed(served),
        ),
    ];
  }

  static String _serverName(ServerKind kind) => switch (kind) {
    ServerKind.lmStudio => 'LM Studio',
    ServerKind.ollama => 'Ollama',
    ServerKind.llamaCpp => 'llama.cpp',
    ServerKind.vllm => 'vLLM',
    ServerKind.unknown => '—',
  };

  Widget _logCard(AppLocalizations l10n, AppTokens t, bool enabled) {
    final dir = ApiLog.instance.directory;
    return AiCard(
      title: l10n.aiLogTitle,
      note: l10n.aiLogHint,
      trailing: AppButton.ghost(
        label: l10n.aiLogOpenFolder,
        height: AppSizes.controlSm,
        onPressed: dir == null
            ? null
            : () => launchUrl(Uri.directory(dir.path)),
      ),
      fill: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      enabled ? l10n.aiLogEmpty : l10n.aiLogOff,
                      style: AppTypeScale.caption.copyWith(color: t.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final entry = _entries[i];
                      // The sequence restarts with the app, the time does not.
                      final id = '${entry['at']}#${entry['seq']}';
                      return _LogRow(
                        entry: entry,
                        expanded: _expanded == id,
                        onTap: () => setState(
                          () => _expanded = _expanded == id ? null : id,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.aiLogFootnote,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  /// true = passed, false = failed, null = undecided.
  final bool? ok;
  final String text;

  const _Step({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (icon, color) = switch (ok) {
      true => (Icons.check_rounded, t.success),
      false => (Icons.error_outline_rounded, t.danger),
      null => (Icons.help_outline_rounded, t.warning),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypeScale.control.copyWith(color: t.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextWarning extends StatelessWidget {
  final int served;
  final int typed;
  final VoidCallback onUse;

  const _ContextWarning({
    required this.served,
    required this.typed,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.warningSurface,
        borderRadius: BorderRadius.circular(AppRadii.field),
        border: Border.all(color: t.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aiStepContext(served, typed),
            style: AppTypeScale.controlStrong.copyWith(color: t.textTitle),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.aiStepContextBody,
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: l10n.aiStepUseServed,
            height: AppSizes.controlSm,
            onPressed: onUse,
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool expanded;
  final VoidCallback onTap;

  const _LogRow({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final response = entry['response'];
    final usage = response is Map ? response['usage'] : null;
    final error = entry['error'];
    final failed = error != null;
    final at = DateTime.tryParse('${entry['at']}');
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}:'
              '${at.second.toString().padLeft(2, '0')}';
    final outcome = failed
        ? '$error'
        : (response is Map ? '${response['finish_reason'] ?? ''}' : '');
    final style = t.monoTiny.copyWith(color: failed ? t.danger : t.textBody);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListRow(
          failed: failed,
          onTap: onTap,
          child: Row(
            children: [
              Text(time, style: style.copyWith(color: t.textMuted)),
              const SizedBox(width: AppSpacing.md),
              Text('#${entry['seq']}', style: style),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${entry['protocol']} · ${entry['model']}'
                  '${entry['status'] == null ? '' : ' · ${entry['status']}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  outcome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: failed ? t.danger : t.success),
                ),
              ),
              if (usage is Map) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${usage['prompt']} / ${usage['completion']}',
                  style: style,
                ),
              ],
            ],
          ),
        ),
        if (expanded)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: t.controlFill,
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert({
                'url': entry['url'],
                'request': entry['request'],
                'response': ?entry['response'],
                'error': ?entry['error'],
              }),
              style: t.monoTiny.copyWith(color: t.textBody),
            ),
          ),
      ],
    );
  }
}
