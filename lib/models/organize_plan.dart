import 'dart:convert';

/// Lifecycle of a single action as it moves through the UI.
enum ActionStatus { pending, applied, needsReview, failed }

/// One move/rename the AI proposes for a single file.
class OrganizeAction {
  /// Path of the file relative to the organized folder (matches the `source`
  /// the model was given). Combined with the folder base path at apply time.
  final String source;

  /// Target path relative to the folder being organized. The first segment is
  /// the library root (e.g. `Movies/...`).
  final String target;

  /// Coarse kind echoed by the model (video / subtitle / image / …).
  final String kind;

  /// Model confidence, 0–1.
  final double confidence;
  final String note;

  ActionStatus status;

  /// Populated after an apply attempt fails.
  String? error;

  OrganizeAction({
    required this.source,
    required this.target,
    required this.kind,
    required this.confidence,
    required this.note,
    ActionStatus? status,
  }) : status = status ?? _initialStatus(confidence);

  static ActionStatus _initialStatus(double confidence) =>
      confidence < 0.6 ? ActionStatus.needsReview : ActionStatus.pending;

  factory OrganizeAction.fromJson(Map<String, dynamic> json) => OrganizeAction(
    source: (json['source'] as String?)?.trim() ?? '',
    target: (json['target'] as String?)?.trim() ?? '',
    kind: (json['kind'] as String?)?.trim() ?? 'other',
    confidence: _asDouble(json['confidence']),
    note: (json['note'] as String?)?.trim() ?? '',
  );

  static double _asDouble(dynamic v) {
    if (v is num) {
      final d = v.toDouble();
      return d > 1 ? (d / 100).clamp(0, 1) : d.clamp(0, 1);
    }
    if (v is String) return _asDouble(num.tryParse(v) ?? 0);
    return 0;
  }
}

/// A full organization proposal for one folder.
class OrganizePlan {
  final String mediaType;
  final String targetRoot;
  final List<String> reasoning;
  final List<OrganizeAction> actions;
  final int promptTokens;
  final int completionTokens;

  OrganizePlan({
    required this.mediaType,
    required this.targetRoot,
    required this.reasoning,
    required this.actions,
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  int get totalTokens => promptTokens + completionTokens;

  /// Parses raw model text into a plan. Tolerant of markdown fences or stray
  /// prose around the JSON object. Throws [FormatException] if no object is
  /// found.
  factory OrganizePlan.fromAiJson(
    String raw, {
    int promptTokens = 0,
    int completionTokens = 0,
  }) {
    final jsonText = _extractJsonObject(raw);
    final Map<String, dynamic> data = jsonDecode(jsonText);
    final actions = (data['actions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(OrganizeAction.fromJson)
        .where((a) => a.source.isNotEmpty && a.target.isNotEmpty)
        .toList();

    return OrganizePlan(
      mediaType: (data['mediaType'] as String?)?.trim() ?? 'unknown',
      targetRoot: (data['targetRoot'] as String?)?.trim() ?? '',
      reasoning: (data['reasoning'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      actions: actions,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  /// Finds the outermost `{ … }` so leading/trailing junk is ignored.
  static String _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw const FormatException('No JSON object found in model response.');
    }
    return raw.substring(start, end + 1);
  }
}
