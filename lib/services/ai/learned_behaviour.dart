/// What the providers learned about a server by being refused or ignored,
/// kept across launches.
///
/// Each of these used to live in a process-wide map, so every launch paid for
/// the same rejections again — and on a cloud platform every step of a ladder
/// is a billed request. Stored per route: protocol, base URL, model and a
/// hash of the key, because what one credential was refused says nothing
/// about another. The key itself is never written.
///
/// A memory goes stale when the server changes under it (an upgrade that
/// learns `json_object`, a model reloaded with another template), so entries
/// expire [maxAge] after they last changed, and the connection test forgets
/// its route's entry before it runs: testing is how a user asks the app to
/// find out again.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class LearnedBehaviour {
  /// The JSON mode the server last accepted (`object`, `schema`, `none`).
  final String? jsonMode;

  /// The model insisted on `max_completion_tokens`.
  final bool maxCompletionTokens;

  /// Optional request fields the server refused by name.
  final Set<String> rejectedFields;

  /// The ways of turning reasoning off that this route ignored or refused,
  /// by name. Names rather than a position in the ladder: the ladder's shape
  /// depends on the server kind, which is detected afresh each launch, and a
  /// stored position would point at a different way once it changed.
  final Set<String> thinkingOffTried;

  /// In [thinkingOffTried]: the model refused its platform's reasoning switch
  /// set to off (Zhipu's 5.3 generation always reasons). No ladder way has
  /// this name, but the set can hold both: a route key has no platform in
  /// it, so a channel whose platform changed keeps what the old one learned.
  static const dialectOff = 'dialect';

  final DateTime updated;

  LearnedBehaviour({
    this.jsonMode,
    this.maxCompletionTokens = false,
    this.rejectedFields = const {},
    this.thinkingOffTried = const {},
    DateTime? updated,
  }) : updated = updated ?? DateTime.now();

  static final empty = LearnedBehaviour(
    updated: DateTime.fromMillisecondsSinceEpoch(0),
  );

  bool get isEmpty =>
      jsonMode == null &&
      !maxCompletionTokens &&
      rejectedFields.isEmpty &&
      thinkingOffTried.isEmpty;

  /// Same memory, whatever its date.
  bool sameAs(LearnedBehaviour other) =>
      jsonMode == other.jsonMode &&
      maxCompletionTokens == other.maxCompletionTokens &&
      rejectedFields.length == other.rejectedFields.length &&
      rejectedFields.containsAll(other.rejectedFields) &&
      thinkingOffTried.length == other.thinkingOffTried.length &&
      thinkingOffTried.containsAll(other.thinkingOffTried);

  LearnedBehaviour copyWith({
    String? jsonMode,
    bool? maxCompletionTokens,
    Set<String>? rejectedFields,
    Set<String>? thinkingOffTried,
  }) => LearnedBehaviour(
    jsonMode: jsonMode ?? this.jsonMode,
    maxCompletionTokens: maxCompletionTokens ?? this.maxCompletionTokens,
    rejectedFields: rejectedFields ?? this.rejectedFields,
    thinkingOffTried: thinkingOffTried ?? this.thinkingOffTried,
    updated: updated,
  );

  /// The same memory, dated [at].
  LearnedBehaviour stamped(DateTime at) => LearnedBehaviour(
    jsonMode: jsonMode,
    maxCompletionTokens: maxCompletionTokens,
    rejectedFields: rejectedFields,
    thinkingOffTried: thinkingOffTried,
    updated: at,
  );

  Map<String, Object?> toJson() => {
    'json_mode': ?jsonMode,
    if (maxCompletionTokens) 'max_completion_tokens': true,
    if (rejectedFields.isNotEmpty)
      'rejected_fields': rejectedFields.toList()..sort(),
    if (thinkingOffTried.isNotEmpty)
      'thinking_off_tried': thinkingOffTried.toList()..sort(),
    'updated': updated.toUtc().toIso8601String(),
  };

  static LearnedBehaviour? fromJson(Object? json) {
    if (json is! Map) return null;
    final updated = DateTime.tryParse('${json['updated']}');
    if (updated == null) return null;
    return LearnedBehaviour(
      jsonMode: json['json_mode'] is String
          ? json['json_mode'] as String
          : null,
      maxCompletionTokens: json['max_completion_tokens'] == true,
      rejectedFields: {
        if (json['rejected_fields'] case final List<dynamic> fields)
          ...fields.whereType<String>(),
      },
      thinkingOffTried: {
        if (json['thinking_off_tried'] case final List<dynamic> tried)
          ...tried.whereType<String>(),
      },
      updated: updated.toLocal(),
    );
  }
}

class LearnedStore {
  LearnedStore({File? file, DateTime Function()? clock})
    : _file = file,
      _clock = clock ?? DateTime.now;

  /// The app-wide store, pointed at `<appSupport>/ai_learned.json` by
  /// `main()`. Without a file it only remembers for the process, which is
  /// what tests get.
  static final LearnedStore instance = LearnedStore();

  static const maxAge = Duration(days: 30);
  static const _saveDebounce = Duration(milliseconds: 250);

  File? _file;
  final DateTime Function() _clock;
  final Map<String, LearnedBehaviour> _entries = {};
  Timer? _saveTimer;

  /// The route key the providers use: [protocol] | [base] | [model] | a
  /// short hash of [apiKey]. SHA-256 rather than `String.hashCode`, which is
  /// not promised to be stable from one run to the next.
  static String routeKey({
    required String protocol,
    required String base,
    required String model,
    required String apiKey,
  }) {
    final key = apiKey.trim();
    final hash = key.isEmpty
        ? '-'
        : sha256.convert(utf8.encode(key)).toString().substring(0, 12);
    // User info typed into an endpoint is a credential too.
    final bare = base.replaceFirst(RegExp(r'//[^/@]*@'), '//');
    return '$protocol|$bare|${model.trim()}|$hash';
  }

  /// Reads [file] and keeps writing to it. Entries older than [maxAge] are
  /// dropped. An unreadable file is an empty store.
  Future<void> load(File file) async {
    _file = file;
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final cutoff = _clock().subtract(maxAge);
      for (final entry in json.entries) {
        final value = LearnedBehaviour.fromJson(entry.value);
        if (value != null && value.updated.isAfter(cutoff)) {
          _entries['${entry.key}'] = value;
        }
      }
    } catch (_) {
      // A lost memory costs one refused request, never correctness.
    }
  }

  LearnedBehaviour of(String key) {
    final value = _entries[key];
    if (value == null) return LearnedBehaviour.empty;
    if (value.updated.isBefore(_clock().subtract(maxAge))) {
      _entries.remove(key);
      return LearnedBehaviour.empty;
    }
    return value;
  }

  /// Applies [change] to [key]'s memory. Nothing is written, and the date is
  /// not moved, unless the memory actually changed — so an entry expires
  /// [maxAge] after it was learned even on a route in daily use.
  void update(String key, LearnedBehaviour Function(LearnedBehaviour) change) {
    final current = of(key);
    final next = change(current);
    if (next.sameAs(current)) return;
    if (next.isEmpty) {
      if (_entries.remove(key) == null) return;
    } else {
      _entries[key] = next.stamped(_clock());
    }
    _scheduleSave();
  }

  /// Forgets everything learned about [key].
  void forget(String key) {
    if (_entries.remove(key) != null) _scheduleSave();
  }

  /// Every remembered route, for the diagnostics view.
  Map<String, LearnedBehaviour> get entries => Map.unmodifiable(_entries);

  void _scheduleSave() {
    if (_file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      _saveTimer = null;
      unawaited(save());
    });
  }

  Future<void> _saving = Future.value();

  /// Writes the store now. Saves are chained, and each writes a temporary
  /// file and renames it over the old one, so two saves never interleave and
  /// a crash mid-write leaves the previous file intact. A change made in the
  /// last [_saveDebounce] before the app quits can be lost; that costs one
  /// refused request next launch, never correctness.
  Future<void> save() {
    final file = _file;
    if (file == null) return _saving;
    final content = jsonEncode({
      for (final entry in _entries.entries) entry.key: entry.value.toJson(),
    });
    return _saving = _saving.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(content, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        // Next change tries again.
      }
    });
  }
}
