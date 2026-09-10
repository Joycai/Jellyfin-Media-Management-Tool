/// Lifecycle of a single action as it moves through the UI.
enum ActionStatus { pending, applied, needsReview, failed }

/// One move/rename proposed for a single file.
class OrganizeAction {
  /// Path of the file relative to the organized folder, as the scan found it.
  /// Combined with the folder base path at apply time.
  final String source;

  /// Target path relative to the folder being organized. The first segment is
  /// the library root (e.g. `Movies/...`).
  ///
  /// Mutable because the preview dialog lets the user correct the proposal
  /// before anything is written — editing the plan in memory keeps every
  /// filesystem write behind `ApplyController`.
  String target;

  /// Coarse kind (video / subtitle / image / metadata / audio / extra / other).
  final String kind;

  /// Confidence, 0–1.
  final double confidence;
  final String note;

  ActionStatus status;

  /// True once the user rewrote [target] in the preview, so the UI can mark the
  /// row as no longer being what was proposed.
  bool userEdited = false;

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
}

/// A full organization proposal for one folder.
class OrganizePlan {
  /// `movie`, `series`, `mixed` or `unknown`.
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
}
