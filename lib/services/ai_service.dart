import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../models/organize_plan.dart';
import 'ai/ai_cancel_token.dart';
import 'ai/ai_prompt.dart';
import 'ai/ai_provider.dart';
import 'ai/connection_check.dart';
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

  /// Builds a provider for the current config.
  ///
  /// Public because the scrape module's recipe learner needs one too, and
  /// duplicating the provider/transport choice there would let the two drift.
  AiProvider buildProvider() => providerFor(_config);

  /// Builds a provider for an arbitrary config.
  ///
  /// Static because the scrape panel lets the user pick a backend for one
  /// scrape without making it the app-wide active profile — so it needs a
  /// provider for a config this service is not holding.
  static AiProvider providerFor(AiConfig config) => switch (config.provider) {
    AiProviderType.googleGenAi => GoogleGenAiProvider(config),
    AiProviderType.openAi => OpenAiProvider(config),
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
    // status; sampling, reasoning and the token budgets do not affect
    // connectivity. Every field is a primitive, so comparing the JSON forms is
    // an exact equality check that cannot fall behind a new field.
    final connectionChanged = !_sameEndpoint(config, _config);
    if (!connectionChanged && mapEquals(config.toJson(), _config.toJson())) {
      return;
    }
    _config = config;
    if (connectionChanged) {
      _status = ConnectionStatus.unknown;
      _statusMessage = null;
    }
    _notifySafely();
  }

  static bool _sameEndpoint(AiConfig a, AiConfig b) =>
      a.provider == b.provider &&
      a.endpoint == b.endpoint &&
      a.apiKey == b.apiKey &&
      a.model == b.model;

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

  /// Runs the Settings connection check against [config]: one real, tiny
  /// completion — see [AiConnectionCheck]. Throws whatever the request threw.
  ///
  /// The sidebar status follows the result only when [config] is the live
  /// endpoint, so testing a standby profile cannot paint the active one green
  /// (or red).
  Future<AiConnectionCheckResult> testConnection(AiConfig config) async {
    if (!config.isComplete) {
      throw const AiException('Incomplete configuration');
    }
    final live = _sameEndpoint(config, _config);
    void report(ConnectionStatus status, [String? message]) {
      if (!live) return;
      _status = status;
      _statusMessage = message;
      notifyListeners();
    }

    report(ConnectionStatus.testing);
    try {
      final result = await AiConnectionCheck.run(providerFor(config));
      report(ConnectionStatus.connected);
      return result;
    } catch (e) {
      report(ConnectionStatus.error, e.toString());
      rethrow;
    }
  }

  /// Analyzes [baseDir] and stores the resulting [OrganizePlan]. Throws
  /// [AiException]/[FormatException] on failure (caller surfaces it).
  ///
  /// When [onlyPaths] is non-empty, only files whose absolute path is in the
  /// set — or that live under a selected directory — are sent to the model,
  /// so the user can organize a subset of the folder.
  ///
  /// Pass a [cancelToken] to make the run abortable: cancelling stops the
  /// directory walk and tears down the in-flight request, and the call
  /// completes with [AiCancelled] without touching [currentPlan].
  Future<OrganizePlan> analyzeFolder(
    String baseDir, {
    String? titleHint,
    String? mediaTypeHint,
    Set<String>? onlyPaths,
    AiCancelToken? cancelToken,
  }) async {
    if (!_config.isComplete) {
      throw const AiException('AI is not configured.');
    }
    _isAnalyzing = true;
    _currentPlan = null;
    _planBaseDir = baseDir;
    notifyListeners();

    try {
      final entries = await _collectEntries(
        baseDir,
        onlyPaths: onlyPaths,
        cancelToken: cancelToken,
      );
      if (entries.isEmpty) {
        throw const AiException('No files to organize in this folder.');
      }
      // Without a token budget this is one batch — the whole folder in one
      // request, as it always was. With one, the folder is split so every
      // request (files in, actions out) fits the model's window, and later
      // batches are told which title folders the earlier ones chose.
      final folderName = p.basename(baseDir);
      final batches = AiPrompt.batchEntries(
        entries,
        config: _config,
        folderName: folderName,
        titleHint: titleHint,
        mediaTypeHint: mediaTypeHint,
      );
      final provider = buildProvider();
      final parts = <OrganizePlan>[];
      for (final batch in batches) {
        cancelToken?.throwIfCancelled();
        final sw = Stopwatch()..start();
        final response = await provider.complete(
          systemPrompt: AiPrompt.systemPrompt,
          userPrompt: AiPrompt.buildUserPrompt(
            folderName: folderName,
            entries: batch,
            titleHint: titleHint,
            mediaTypeHint: mediaTypeHint,
            knownFolders: AiPrompt.titleFolders(
              parts.expand((part) => part.actions).map((a) => a.target),
            ),
          ),
          cancelToken: cancelToken,
        );
        sw.stop();
        // A cancel that lands between the response arriving and the plan being
        // stored must still win — otherwise the panel pops a plan the user
        // already dismissed.
        cancelToken?.throwIfCancelled();
        _requestCount++;
        _latencies.add(sw.elapsedMilliseconds);
        if (_latencies.length > 12) _latencies.removeAt(0);
        parts.add(_parsePlan(response));
      }
      final plan = OrganizePlan.merge(parts);

      _currentPlan = plan;
      _lastTokens = plan.totalTokens;
      _totalTokens += plan.totalTokens;
      _itemsProcessed += plan.actions.length;
      _status = ConnectionStatus.connected;
      _statusMessage = null;
      return plan;
    } finally {
      cancelToken?.dispose();
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Parses one batch's reply, naming the likely cause when it was cut off: a
  /// small model's output cap runs out long before a folder of files does, and
  /// a bare "no JSON object found" gives the user nothing to act on.
  static OrganizePlan _parsePlan(AiResponse response) {
    try {
      return OrganizePlan.fromAiJson(
        response.text,
        promptTokens: response.promptTokens,
        completionTokens: response.completionTokens,
      );
    } on FormatException {
      if (!response.truncated) rethrow;
      throw AiException(
        'The model stopped at its output limit '
        '(${response.completionTokens} tokens) before finishing the plan. '
        'Raise "Max output tokens", or set the context window so the folder '
        'is sent in smaller batches.',
      );
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
  ///
  /// With a non-empty [onlyPaths], a file is kept only if its own path is
  /// selected or one of its ancestor directories is (selecting a folder
  /// includes everything inside it).
  Future<List<MediaEntryInput>> _collectEntries(
    String baseDir, {
    Set<String>? onlyPaths,
    AiCancelToken? cancelToken,
  }) async {
    const cap = 400;
    final dir = Directory(baseDir);
    final entries = <MediaEntryInput>[];
    if (!await dir.exists()) return entries;

    bool included(String path) {
      if (onlyPaths == null || onlyPaths.isEmpty) return true;
      var current = p.normalize(path);
      while (true) {
        if (onlyPaths.contains(current)) return true;
        final parent = p.dirname(current);
        // Stop once we pass baseDir (or hit the filesystem root).
        if (parent == current || p.equals(current, baseDir)) return false;
        current = parent;
      }
    }

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      cancelToken?.throwIfCancelled();
      if (entity is! File) continue;
      if (!included(entity.path)) continue;
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
