import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../models/organize_plan.dart';
import 'ai/ai_prompt.dart';
import 'ai/ai_provider.dart';
import 'ai/google_genai_provider.dart';
import 'ai/openai_provider.dart';
import 'file_label_service.dart';

enum ConnectionStatus { unknown, testing, connected, error }

/// Owns the AI configuration, drives folder analysis, and applies the resulting
/// plan. Registered as a `ChangeNotifier` so the assistant panel and the file
/// table rebuild as analysis progresses.
class AiService extends ChangeNotifier {
  AiConfig _config = AiConfig.empty;

  ConnectionStatus _status = ConnectionStatus.unknown;
  String? _statusMessage;

  bool _isAnalyzing = false;
  OrganizePlan? _currentPlan;

  /// Absolute path of the folder the current plan was built for.
  String? _planBaseDir;

  int _lastTokens = 0;
  int _totalTokens = 0;
  int _itemsProcessed = 0;
  int _requestCount = 0;
  final List<int> _latencies = [];

  AiConfig get config => _config;
  ConnectionStatus get status => _status;
  String? get statusMessage => _statusMessage;
  bool get isAnalyzing => _isAnalyzing;
  OrganizePlan? get currentPlan => _currentPlan;
  String? get planBaseDir => _planBaseDir;
  bool get isConfigured => _config.isComplete;
  int get lastTokens => _lastTokens;
  int get totalTokens => _totalTokens;
  int get itemsProcessed => _itemsProcessed;
  int get requestCount => _requestCount;

  /// Mean request latency in ms (0 when nothing has run yet).
  int get avgLatencyMs => _latencies.isEmpty
      ? 0
      : (_latencies.reduce((a, b) => a + b) / _latencies.length).round();

  /// Recent per-request latencies (newest last), for the usage sparkline.
  List<int> get recentLatencies => List.unmodifiable(_latencies);

  AiProvider _buildProvider() => switch (_config.provider) {
    AiProviderType.googleGenAi => GoogleGenAiProvider(_config),
    AiProviderType.openAi => OpenAiProvider(_config),
  };

  /// Syncs config from settings. Resets the connection status when the target
  /// endpoint/model changes so the UI doesn't show a stale "connected".
  ///
  /// This is called from `build()` (the settings section re-syncs on rebuild),
  /// so it must not notify when nothing changed, and must never notify
  /// synchronously during a build — both would trigger
  /// "setState()/markNeedsBuild() called during build".
  void updateConfig(AiConfig config) {
    // A change to any connection-relevant field invalidates a prior "connected"
    // status; temperature does not affect connectivity.
    final connectionChanged =
        config.provider != _config.provider ||
        config.endpoint != _config.endpoint ||
        config.apiKey != _config.apiKey ||
        config.model != _config.model;
    if (!connectionChanged && config.temperature == _config.temperature) return;
    _config = config;
    if (connectionChanged) {
      _status = ConnectionStatus.unknown;
      _statusMessage = null;
    }
    _notifySafely();
  }

  /// Notifies listeners, deferring to after the current frame if we're mid-build
  /// (a listener watching this service could otherwise be rebuilt during build).
  void _notifySafely() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  Future<bool> testConnection() async {
    if (!_config.isComplete) {
      _status = ConnectionStatus.error;
      _statusMessage = 'Incomplete configuration';
      notifyListeners();
      return false;
    }
    _status = ConnectionStatus.testing;
    _statusMessage = null;
    notifyListeners();
    try {
      final ok = await _buildProvider().testConnection();
      _status = ok ? ConnectionStatus.connected : ConnectionStatus.error;
      _statusMessage = ok ? null : 'Unexpected response';
      notifyListeners();
      return ok;
    } catch (e) {
      _status = ConnectionStatus.error;
      _statusMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Analyzes [baseDir] and stores the resulting [OrganizePlan]. Throws
  /// [AiException]/[FormatException] on failure (caller surfaces it).
  Future<OrganizePlan> analyzeFolder(
    String baseDir, {
    String? titleHint,
    String? mediaTypeHint,
  }) async {
    if (!_config.isComplete) {
      throw const AiException('AI is not configured.');
    }
    _isAnalyzing = true;
    _currentPlan = null;
    _planBaseDir = baseDir;
    notifyListeners();

    try {
      final entries = await _collectEntries(baseDir);
      if (entries.isEmpty) {
        throw const AiException('No files to organize in this folder.');
      }
      final sw = Stopwatch()..start();
      final response = await _buildProvider().complete(
        systemPrompt: AiPrompt.systemPrompt,
        userPrompt: AiPrompt.buildUserPrompt(
          folderName: p.basename(baseDir),
          entries: entries,
          titleHint: titleHint,
          mediaTypeHint: mediaTypeHint,
        ),
      );
      sw.stop();
      _requestCount++;
      _latencies.add(sw.elapsedMilliseconds);
      if (_latencies.length > 12) _latencies.removeAt(0);
      final plan = OrganizePlan.fromAiJson(
        response.text,
        promptTokens: response.promptTokens,
        completionTokens: response.completionTokens,
      );

      _currentPlan = plan;
      _lastTokens = response.totalTokens;
      _totalTokens += response.totalTokens;
      _itemsProcessed += plan.actions.length;
      _status = ConnectionStatus.connected;
      _statusMessage = null;
      return plan;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  void clearPlan() {
    _currentPlan = null;
    _planBaseDir = null;
    notifyListeners();
  }

  /// Walks [baseDir] recursively (capped) collecting media-relevant files with
  /// their folder-relative path, size, and coarse kind. Streams entries via
  /// async `list()` so big trees don't freeze the UI between user click and
  /// model request.
  Future<List<MediaEntryInput>> _collectEntries(String baseDir) async {
    const cap = 400;
    final dir = Directory(baseDir);
    final entries = <MediaEntryInput>[];
    if (!await dir.exists()) return entries;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue; // skip hidden/system files
      int size;
      try {
        size = await entity.length();
      } catch (_) {
        continue;
      }
      entries.add(
        MediaEntryInput(
          relativePath: p.relative(entity.path, from: baseDir),
          sizeBytes: size,
          kind: FileLabelService.getLabel(p.extension(entity.path)),
        ),
      );
      if (entries.length >= cap) break;
    }
    return entries;
  }
}
