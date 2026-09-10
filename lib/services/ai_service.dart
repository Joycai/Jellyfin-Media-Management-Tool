import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../models/organize_plan.dart';
import 'ai/ai_cancel_token.dart';
import 'ai/ai_provider.dart';
import 'ai/connection_check.dart';
import 'ai/google_genai_provider.dart';
import 'ai/openai_provider.dart';
import 'organize/filename_parser.dart';
import 'organize/jellyfin_naming.dart';
import 'organize/organize_agent.dart';

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

  /// Told when a run finds out whether a model calls tools, so the owner of
  /// the profiles can record it. Wired in `main.dart`.
  void Function(AiConfig config, bool supported)? onToolSupport;

  static const toolsRequiredMessage =
      'This model does not call tools, which organizing and scraping need. '
      'Choose a model that supports tool calling, then run the connection '
      'test in Settings.';

  /// Makes sure [config]'s model calls tools, which every agent task needs —
  /// there is no single-shot fallback. A model never checked is probed once
  /// and the answer recorded through [onToolSupport]. Throws [AiException]
  /// when it cannot call tools.
  Future<void> ensureTools(
    AiConfig config, {
    AiCancelToken? cancelToken,
  }) async {
    var supported = config.supportsTools;
    if (supported == null) {
      supported = await AiConnectionCheck.probeTools(
        providerFor(config),
        cancelToken: cancelToken,
      );
      onToolSupport?.call(config, supported);
    }
    if (!supported) throw const AiException(toolsRequiredMessage);
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
  /// [AiException] on failure (caller surfaces it).
  ///
  /// The files are parsed and grouped in code, and [OrganizeAgent] has the
  /// model decide each group through tool calls; see there for why.
  ///
  /// When [onlyPaths] is non-empty, only files whose absolute path is in the
  /// set — or that live under a selected directory — are organized, so the
  /// user can organize a subset of the folder.
  ///
  /// Pass a [cancelToken] to make the run abortable: cancelling stops the
  /// directory walk and tears down the in-flight request, and the call
  /// completes with [AiCancelled] without touching [currentPlan].
  /// [onProgress] receives the fraction of groups decided so far.
  Future<OrganizePlan> analyzeFolder(
    String baseDir, {
    String? titleHint,
    String? mediaTypeHint,
    Set<String>? onlyPaths,
    AiCancelToken? cancelToken,
    void Function(double fraction)? onProgress,
  }) async {
    if (!_config.isComplete) {
      throw const AiException('AI is not configured.');
    }
    _isAnalyzing = true;
    _currentPlan = null;
    _planBaseDir = baseDir;
    notifyListeners();

    try {
      final paths = await _collectFiles(
        baseDir,
        onlyPaths: onlyPaths,
        cancelToken: cancelToken,
      );
      if (paths.isEmpty) {
        throw const AiException('No files to organize in this folder.');
      }
      final config = _config;
      final sw = Stopwatch()..start();
      final run =
          await OrganizeAgent(
            providerFor(config),
            beforeStart: () => ensureTools(config, cancelToken: cancelToken),
          ).run(
            folderName: p.basename(baseDir),
            files: [for (final path in paths) FilenameParser.parse(path)],
            titleHint: titleHint,
            typeHint: switch (mediaTypeHint) {
              'movie' => GroupMediaType.movie,
              'series' => GroupMediaType.series,
              _ => null,
            },
            readFile: (relativePath) =>
                _readSmallFile(p.join(baseDir, relativePath)),
            cancelToken: cancelToken,
            onProgress: onProgress == null
                ? null
                : (resolved, total) =>
                      onProgress(total == 0 ? 1 : resolved / total),
          );
      sw.stop();
      // A cancel that lands between the last reply and the plan being stored
      // must still win — otherwise the panel pops a plan the user already
      // dismissed.
      cancelToken?.throwIfCancelled();
      if (run.rounds > 0) {
        _requestCount += run.rounds;
        _latencies.add(sw.elapsedMilliseconds ~/ run.rounds);
        if (_latencies.length > 12) _latencies.removeAt(0);
      }
      final plan = run.plan;

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

  void clearPlan() {
    _currentPlan = null;
    _planBaseDir = null;
    notifyListeners();
  }

  /// An NFO the model asked to read. Anything this large is not metadata
  /// worth a model's context, and an unreadable file is simply "no NFO".
  static Future<String?> _readSmallFile(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 512 * 1024) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Walks [baseDir] recursively (capped at 400, dotfiles skipped) and returns
  /// each file's folder-relative path. Streams entries via async `list()` so
  /// big trees don't freeze the UI between user click and model request.
  ///
  /// With a non-empty [onlyPaths], a file is kept only if its own path is
  /// selected or one of its ancestor directories is (selecting a folder
  /// includes everything inside it).
  Future<List<String>> _collectFiles(
    String baseDir, {
    Set<String>? onlyPaths,
    AiCancelToken? cancelToken,
  }) async {
    const cap = 400;
    final dir = Directory(baseDir);
    final paths = <String>[];
    if (!await dir.exists()) return paths;

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
      if (p.basename(entity.path).startsWith('.')) continue;
      paths.add(p.relative(entity.path, from: baseDir));
      if (paths.length >= cap) break;
    }
    return paths;
  }
}
