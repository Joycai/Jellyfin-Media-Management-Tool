import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/ai_channel.dart';
import '../../utils/ids.dart';
import './ai_provider.dart';

/// A model together with the channel it hangs off.
typedef ChannelModel = ({AiChannel channel, AiModelEntry model});

/// Owns the AI channels, their routes and models, and which model each task
/// runs on. Persists to its own `ai_profiles.json` so editing a channel
/// doesn't rewrite the theme/locale/glass config — and a slider drag never
/// thrashes the AI keys file.
///
/// **Reading older files.** A file without `channels` holds flat profiles
/// (`ai_services`); each becomes one channel with one route and one model,
/// built by [AiChannel.fromLegacyProfile] so the requests it sends are
/// byte-for-byte what they were, and the old active profile becomes the
/// organize model. Nothing is rewritten until something changes. The legacy
/// `config.json` keys (`ai_services` / `active_ai_service` / the older `ai`
/// block) are read on the very first launch, as before.
///
/// **Writing.** `channels` and `tasks` are the truth. Beside them the file
/// keeps writing `ai_services` — one flat profile per model on its current
/// route — and `active_ai_service`, so an older build opened on the same
/// folder still finds a working profile. It sees nothing it did not have.
class AiProfilesService extends ChangeNotifier {
  List<AiChannel> _channels = [];
  Map<AiTask, String> _tasks = {};

  static const _saveDebounce = Duration(milliseconds: 250);
  static const schemaVersion = 2;
  Timer? _saveTimer;

  List<AiChannel> get channels => List.unmodifiable(_channels);

  /// Explicit assignments only. A task missing here follows organize — see
  /// [resolve].
  Map<AiTask, String> get tasks => Map.unmodifiable(_tasks);

  /// Every model on every channel, in channel order.
  List<ChannelModel> get allModels => [
    for (final channel in _channels)
      for (final model in channel.models) (channel: channel, model: model),
  ];

  ChannelModel? modelById(String? id) {
    if (id == null) return null;
    for (final channel in _channels) {
      if (channel.model(id) case final model?) {
        return (channel: channel, model: model);
      }
    }
    return null;
  }

  AiChannel? channelById(String id) {
    for (final channel in _channels) {
      if (channel.id == id) return channel;
    }
    return null;
  }

  /// The model [task] runs on: its own assignment, else organize's, else the
  /// first model there is. Null only with no models at all.
  ChannelModel? resolve(AiTask task) =>
      modelById(_tasks[task]) ??
      modelById(_tasks[AiTask.organize]) ??
      allModels.firstOrNull;

  /// Whether [task] has an assignment of its own rather than following
  /// organize.
  bool isAssigned(AiTask task) => modelById(_tasks[task]) != null;

  /// The flat config [task] runs with, or [AiConfig.empty].
  AiConfig configFor(AiTask task) {
    final resolved = resolve(task);
    return resolved == null
        ? AiConfig.empty
        : resolved.channel.configFor(resolved.model);
  }

  /// Runtime config for organizing (consumed by [AiService]).
  AiConfig get aiConfig => configFor(AiTask.organize);

  /// The model frame recognition runs on, or null when there is none the
  /// user has allowed to see images. Unlike the other tasks, falling back to
  /// organize's model is only allowed when that model may see images too:
  /// frames never go to a model the user did not authorise for them.
  AiConfig? get visionConfig {
    final entry = resolve(AiTask.vision);
    if (entry == null || !entry.model.imageInput) return null;
    return entry.channel.configFor(entry.model);
  }

  Future<Directory> get _dir async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> get _file async =>
      File(p.join((await _dir).path, 'ai_profiles.json'));
  Future<File> get _legacyConfig async =>
      File(p.join((await _dir).path, 'config.json'));

  Future<void> init() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          loadFromMap(jsonDecode(content) as Map<String, dynamic>);
        }
      } else {
        await _migrateFromLegacy();
      }
    } catch (e) {
      debugPrint('Error loading ai profiles: $e');
    }
    notifyListeners();
  }

  Future<void> _migrateFromLegacy() async {
    final legacy = await _legacyConfig;
    if (!await legacy.exists()) return;
    try {
      final content = await legacy.readAsString();
      if (content.isEmpty) return;
      loadFromMap(jsonDecode(content) as Map<String, dynamic>);
      // Stamp our own file with the migrated state so we don't re-read the
      // legacy keys on the next launch.
      _scheduleSave();
    } catch (_) {
      // Best-effort migration; if the legacy file is malformed we just stay
      // empty and the user re-adds their channel in onboarding/settings.
    }
  }

  /// Reads any shape this file has had. Public for tests.
  @visibleForTesting
  void loadFromMap(Map<String, dynamic> data) {
    if (data['channels'] is List) {
      _channels = [
        for (final raw in data['channels'] as List)
          if (AiChannel.fromJson(raw) case final AiChannel channel) channel,
      ];
      _tasks = {
        if (data['tasks'] case final Map<dynamic, dynamic> tasks)
          for (final entry in tasks.entries)
            if (AiTask.fromId('${entry.key}') case final AiTask task)
              if (entry.value case final String id) task: id,
      };
    } else if (data['ai_services'] is List) {
      _channels = [
        for (final raw in data['ai_services'] as List)
          if (raw case final Map<String, dynamic> json)
            AiChannel.fromLegacyProfile(
              id: (json['id'] as String?) ?? newId(),
              name: (json['name'] as String?) ?? 'AI Service',
              config: AiConfig.fromJson(json),
            ),
      ];
      final active = data['active_ai_service'];
      _tasks = {
        if (active is String && modelById(active) != null)
          AiTask.organize: active,
      };
    } else if (data['ai'] is Map<String, dynamic>) {
      // Oldest single-endpoint shape. Only the temperature was ever stored
      // beside the connection, as before.
      final cfg = AiConfig.fromJson(data['ai']);
      final channel = AiChannel.fromLegacyProfile(
        id: newId(),
        name: cfg.provider == AiProviderType.googleGenAi
            ? 'Google GenAI'
            : 'OpenAI',
        config: AiConfig(
          provider: cfg.provider,
          endpoint: cfg.endpoint,
          apiKey: cfg.apiKey,
          model: cfg.model,
          temperature: cfg.temperature,
        ),
      );
      _channels = [channel];
      _tasks = {AiTask.organize: channel.models.first.id};
    }
  }

  /// What is written to disk. Public for tests.
  @visibleForTesting
  Map<String, Object?> toMap() {
    // An older build knows two protocols and reads any other as Chat
    // Completions, so only models it can really drive are mirrored for it.
    bool olderBuildSpeaks(ChannelModel entry) =>
        switch (entry.channel.configFor(entry.model).provider) {
          AiProviderType.openAi || AiProviderType.googleGenAi => true,
          _ => false,
        };
    final mirrored = allModels.where(olderBuildSpeaks).toList();
    final organize = resolve(AiTask.organize);
    final active = organize != null && olderBuildSpeaks(organize)
        ? organize.model.id
        : mirrored.firstOrNull?.model.id;
    return {
      'v': schemaVersion,
      'channels': [for (final channel in _channels) channel.toJson()],
      'tasks': {for (final entry in _tasks.entries) entry.key.id: entry.value},
      // For an older build opened on the same folder.
      'ai_services': [
        for (final (:channel, :model) in mirrored)
          {
            'id': model.id,
            'name': channel.models.length == 1
                ? channel.name
                : '${channel.name} · ${model.upstream}',
            ...channel.configFor(model).toJson(),
          },
      ],
      'active_ai_service': active,
    };
  }

  void _changed() {
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(toMap()));
    } catch (e) {
      debugPrint('Error saving ai profiles: $e');
    }
  }

  @override
  void dispose() {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      unawaited(_save());
    }
    super.dispose();
  }

  // ── Channels ──────────────────────────────────────────────────────────────

  /// Adds [channel]. The first model anywhere becomes the organize model, so
  /// a fresh install works as soon as one exists.
  Future<void> addChannel(AiChannel channel) async {
    _channels = [..._channels, channel];
    _claimOrganize();
    _changed();
  }

  /// Replaces a channel in place (matched by id).
  Future<void> updateChannel(AiChannel channel) async {
    final index = _channels.indexWhere((c) => c.id == channel.id);
    if (index < 0) return;
    _channels = [..._channels]..[index] = channel;
    _dropDanglingTasks();
    _claimOrganize();
    _changed();
  }

  Future<void> deleteChannel(String id) async {
    _channels = _channels.where((c) => c.id != id).toList();
    _dropDanglingTasks();
    _claimOrganize();
    _changed();
  }

  // ── Models ────────────────────────────────────────────────────────────────

  /// Adds or replaces [model] on the channel [channelId].
  Future<void> upsertModel(String channelId, AiModelEntry model) async {
    final channel = channelById(channelId);
    if (channel == null) return;
    await updateChannel(channel.withModel(model));
  }

  Future<void> deleteModel(String channelId, String modelId) async {
    final channel = channelById(channelId);
    if (channel == null) return;
    await updateChannel(
      channel.copyWith(
        models: channel.models.where((m) => m.id != modelId).toList(),
      ),
    );
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────

  /// Points [task] at [modelId], or back at organize's model with null.
  /// Organize itself cannot be unassigned while a model exists.
  Future<void> assign(AiTask task, String? modelId) async {
    if (modelId != null && modelById(modelId) == null) return;
    if (modelId == null) {
      if (task == AiTask.organize) return;
      _tasks = {..._tasks}..remove(task);
    } else {
      _tasks = {..._tasks, task: modelId};
    }
    _changed();
  }

  void _dropDanglingTasks() {
    _tasks = {
      for (final entry in _tasks.entries)
        if (modelById(entry.value) != null) entry.key: entry.value,
    };
  }

  void _claimOrganize() {
    if (modelById(_tasks[AiTask.organize]) != null) return;
    final first = allModels.firstOrNull;
    if (first == null) {
      _tasks = {..._tasks}..remove(AiTask.organize);
    } else {
      _tasks = {..._tasks, AiTask.organize: first.model.id};
    }
  }

  // ── Measurements ──────────────────────────────────────────────────────────

  /// Records whether a model called tools, on every model whose current
  /// route resolves to the same protocol, endpoint and model name — the
  /// answer belongs to that, not to whichever entry ran the check. Returns
  /// whether anything changed.
  bool recordToolSupport(AiConfig tested, bool supported) {
    var changed = false;
    _channels = [
      for (final channel in _channels)
        channel.copyWith(
          models: [
            for (final model in channel.models)
              if (channel.configFor(model) case final config
                  when config.toolFingerprint == tested.toolFingerprint &&
                      config.supportsTools != supported)
                () {
                  changed = true;
                  // Under the protocol that was measured, which is the
                  // model's route unless that route has since been removed.
                  final measured = config.withToolSupport(supported);
                  return model.copyWith(
                    params: {
                      ...model.params,
                      config.provider: RouteParams.fromConfig(measured),
                    },
                  );
                }()
              else
                model,
          ],
        ),
    ];
    if (changed) _changed();
    return changed;
  }

  // ── Merging ───────────────────────────────────────────────────────────────

  /// Groups of channels that are really one: the same host and the same
  /// non-empty key, with no protocol claimed twice at different endpoints.
  /// Migrated profiles for one relay (one per protocol, or one per model)
  /// show up here; nothing is merged without the user's say-so.
  List<List<AiChannel>> get mergeCandidates {
    final groups = <String, List<AiChannel>>{};
    for (final channel in _channels) {
      final key = channel.apiKey.trim();
      final uri = Uri.tryParse(channel.baseUrl.trim());
      if (key.isEmpty || uri == null || uri.host.isEmpty) continue;
      groups.putIfAbsent('${uri.host}:${uri.port}|$key', () => []).add(channel);
    }
    return [
      for (final group in groups.values)
        if (group.length > 1 && _mergeable(group)) group,
    ];
  }

  static bool _mergeable(List<AiChannel> group) {
    // One platform, or a model moving over would change what it is sent.
    if (group.map((c) => c.platform.id).toSet().length > 1) return false;
    final endpoints = <AiProviderType, String>{};
    for (final channel in group) {
      for (final route in channel.routes) {
        final endpoint = channel.endpointFor(route.protocol);
        final seen = endpoints[route.protocol];
        if (seen != null && seen != endpoint) return false;
        endpoints[route.protocol] = endpoint;
      }
    }
    return true;
  }

  /// Folds [ids] into the first of them: routes are united (each keeps its
  /// endpoint), models move over with their parameters and ids, so task
  /// assignments still point where they did.
  Future<void> merge(List<String> ids) async {
    final group = [for (final id in ids) ?channelById(id)];
    if (group.length < 2 || !_mergeable(group)) return;
    final first = group.first;
    final routes = <AiProviderType, AiRoute>{};
    for (final channel in group) {
      for (final route in channel.routes) {
        routes.putIfAbsent(
          route.protocol,
          () => AiRoute(
            protocol: route.protocol,
            endpoint: channel.endpointFor(route.protocol),
          ),
        );
      }
    }
    final merged = first.copyWith(
      routes: routes.values.toList(),
      models: [for (final channel in group) ...channel.models],
    );
    _channels = [
      for (final channel in _channels)
        if (channel.id == first.id)
          merged
        else if (!ids.contains(channel.id))
          channel,
    ];
    _changed();
  }
}
