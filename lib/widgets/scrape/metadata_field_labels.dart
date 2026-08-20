/// Localized names for [MetadataField] keys, and the human-readable rendering
/// of a field's value.
///
/// One mapping in one place: the preview table, the image grid and any future
/// scrape UI all read from here rather than each growing its own 19-arm switch.
library;

import '../../l10n/app_localizations.dart';
import '../../models/media_metadata.dart';

/// Display name of [field], falling back to the raw key for anything a recipe
/// invented that we don't have a string for.
String metadataFieldLabel(AppLocalizations l10n, String field) =>
    switch (field) {
      MetadataField.title => l10n.fieldTitle,
      MetadataField.originalTitle => l10n.fieldOriginalTitle,
      MetadataField.sortTitle => l10n.fieldSortTitle,
      MetadataField.code => l10n.fieldCode,
      MetadataField.plot => l10n.fieldPlot,
      MetadataField.outline => l10n.fieldOutline,
      MetadataField.tagline => l10n.fieldTagline,
      MetadataField.premiered => l10n.fieldPremiered,
      MetadataField.runtimeMinutes => l10n.fieldRuntime,
      MetadataField.studio => l10n.fieldStudio,
      MetadataField.series => l10n.fieldSeries,
      MetadataField.director => l10n.fieldDirector,
      MetadataField.rating => l10n.fieldRating,
      MetadataField.genres => l10n.fieldGenres,
      MetadataField.tags => l10n.fieldTags,
      MetadataField.actors => l10n.fieldActors,
      MetadataField.poster => l10n.fieldPoster,
      MetadataField.fanart => l10n.fieldFanart,
      MetadataField.extraFanart => l10n.fieldExtraFanart,
      _ => field,
    };

/// Where a value came from, as a short badge label.
String fieldOriginLabel(AppLocalizations l10n, FieldOrigin origin) =>
    switch (origin) {
      FieldOrigin.structuredData => l10n.scrapeOriginStructured,
      FieldOrigin.recipe => l10n.scrapeOriginRecipe,
      FieldOrigin.llm => l10n.scrapeOriginLlm,
      FieldOrigin.existingNfo => l10n.scrapeOriginExisting,
      FieldOrigin.manual => l10n.scrapeOriginManual,
      FieldOrigin.derived => l10n.scrapeOriginDerived,
      FieldOrigin.merged => l10n.scrapeOriginMerged,
    };

/// One-line rendering of a field's value; empty string when there is none.
///
/// Lists are joined rather than truncated — the cell itself ellipsizes, and a
/// "+3 more" suffix would hide exactly the entries the user is checking.
String metadataValueText(MediaMetadata? metadata, String field) {
  final value = metadata?.get(field);
  if (value == null) return '';
  if (value is List) {
    return value.map((e) => e.toString()).join(', ');
  }
  return value.toString();
}

/// The same value in the form the inline editor round-trips.
///
/// Lists become `a, b, c` and are split back on commas by
/// [parseMetadataValue], so editing them needs no separate list editor.
String metadataEditText(MediaMetadata metadata, String field) =>
    metadataValueText(metadata, field);

/// Turns edited text back into something [MediaMetadata.set] accepts.
///
/// Returns null for an empty edit, which `set` ignores — clearing a field is
/// expressed by choosing "keep" on the row, not by blanking the box, because a
/// blank scraped value has no meaning to write.
Object? parseMetadataValue(String field, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (MetadataField.listFields.contains(field)) {
    return [
      for (final part in trimmed.split(',')) part.trim(),
    ].where((s) => s.isNotEmpty).toList();
  }
  return trimmed;
}

/// Fields the inline editor offers.
///
/// Actors are excluded on purpose: a cast entry carries a role and a headshot
/// URL that a comma-separated box would silently throw away.
bool isFieldEditable(String field) => field != MetadataField.actors;

/// Fields that need a text area rather than a single line.
bool isFieldMultiline(String field) =>
    field == MetadataField.plot || field == MetadataField.outline;
