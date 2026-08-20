/// Field-level reconciliation between an NFO already on disk and a fresh
/// scrape.
///
/// The whole point of the feature: re-scraping a title must never be an
/// all-or-nothing overwrite. Every field gets its own decision, the defaults
/// are chosen so the *safe* thing happens if the user just presses OK, and the
/// three presets cover the cases people actually want.
library;

import '../../models/media_metadata.dart';

/// What to do with one field.
enum MergeDecision {
  /// Leave the value that is already on disk.
  keep,

  /// Take the scraped value.
  replace,

  /// List fields only: union of both, existing entries first.
  merge,
}

/// The one-click starting points offered above the field table.
enum MergePreset {
  /// Only write fields the existing NFO does not have. The safest, and the
  /// default when an NFO is already present.
  fillEmptyOnly,

  /// Take everything from the scrape.
  replaceAll,

  /// Change nothing (useful for reviewing a diff before committing to it).
  keepAll,
}

class NfoMergePlan {
  /// Field key -> decision. Only fields that differ are present; identical
  /// values need no decision and are not shown.
  final Map<String, MergeDecision> decisions;

  /// Fields present in the scrape but absent (blank) on disk.
  final Set<String> newFields;

  /// Fields where both sides have a value and they differ.
  final Set<String> conflictFields;

  const NfoMergePlan({
    required this.decisions,
    required this.newFields,
    required this.conflictFields,
  });

  bool get isEmpty => decisions.isEmpty;

  MergeDecision decisionFor(String field) =>
      decisions[field] ?? MergeDecision.keep;

  NfoMergePlan withDecision(String field, MergeDecision decision) =>
      NfoMergePlan(
        decisions: {...decisions, field: decision},
        newFields: newFields,
        conflictFields: conflictFields,
      );

  NfoMergePlan withPreset(MergePreset preset) => NfoMergePlan(
    decisions: {
      for (final field in decisions.keys)
        field: switch (preset) {
          MergePreset.keepAll => MergeDecision.keep,
          MergePreset.replaceAll => MergeDecision.replace,
          MergePreset.fillEmptyOnly =>
            newFields.contains(field)
                ? MergeDecision.replace
                : MergeDecision.keep,
        },
    },
    newFields: newFields,
    conflictFields: conflictFields,
  );
}

class NfoMerge {
  /// Builds the default plan.
  ///
  /// Defaults, in order of precedence:
  ///
  /// * the existing value is blank -> **replace** (pure gain, nothing lost);
  /// * the scraped value came from the LLM -> **keep** (a guess must not
  ///   silently overwrite something a human or another scraper wrote);
  /// * it is a list field -> **merge** (genres and tags accumulate; that is
  ///   almost always what re-scraping is for);
  /// * otherwise -> **keep**, and the field is flagged as a conflict so the
  ///   preview draws attention to it.
  ///
  /// Note the asymmetry: a *new* field is taken automatically, a *conflicting*
  /// one is not. Adding information is safe, replacing it is a judgement call.
  static NfoMergePlan suggest(MediaMetadata? existing, MediaMetadata scraped) {
    final decisions = <String, MergeDecision>{};
    final newFields = <String>{};
    final conflicts = <String>{};

    for (final field in MetadataField.all) {
      if (scraped.isBlank(field)) continue;

      if (existing == null || existing.isBlank(field)) {
        decisions[field] = MergeDecision.replace;
        newFields.add(field);
        continue;
      }
      if (_sameValue(existing.get(field), scraped.get(field))) continue;

      conflicts.add(field);
      final origin = scraped.origins[field];
      if (origin == FieldOrigin.llm) {
        decisions[field] = MergeDecision.keep;
      } else if (MetadataField.listFields.contains(field)) {
        decisions[field] = MergeDecision.merge;
      } else {
        decisions[field] = MergeDecision.keep;
      }
    }

    return NfoMergePlan(
      decisions: decisions,
      newFields: newFields,
      conflictFields: conflicts,
    );
  }

  /// Applies [plan] and returns the metadata that should be written.
  ///
  /// Starts from a copy of [existing] so unmanaged-but-known fields survive
  /// untouched; fields with no decision are left exactly as they were.
  static MediaMetadata resolve(
    MediaMetadata? existing,
    MediaMetadata scraped,
    NfoMergePlan plan,
  ) {
    final out = existing?.copy() ?? MediaMetadata();

    for (final entry in plan.decisions.entries) {
      final field = entry.key;
      final decision = entry.value;
      if (decision == MergeDecision.keep) continue;
      final value = decision == MergeDecision.merge
          ? _union(out.get(field), scraped.get(field))
          : scraped.get(field);
      final origin = decision == MergeDecision.merge
          ? FieldOrigin.merged
          : (scraped.origins[field] ?? FieldOrigin.recipe);
      out.set(field, value, origin);
    }
    // The source URL always reflects the most recent scrape, whatever the
    // field decisions were — it is provenance, not content.
    out.sourceUrl = scraped.sourceUrl ?? out.sourceUrl;
    return out;
  }

  /// Existing entries first, then scraped ones that are not already present.
  static Object? _union(Object? existing, Object? scraped) {
    if (existing is! List) return scraped;
    if (scraped is! List) return existing;
    final out = <Object>[...existing];
    for (final item in scraped) {
      if (!out.contains(item)) out.add(item);
    }
    return out;
  }

  static bool _sameValue(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }
}
