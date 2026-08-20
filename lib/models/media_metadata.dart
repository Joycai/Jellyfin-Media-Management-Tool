/// The metadata a scrape produces for one title, plus where each field came
/// from. Deliberately mutable: the preview dialog edits it in place, which
/// keeps every disk write behind `MetadataWriter` (same rule that makes
/// `OrganizeAction.target` mutable for the organize preview).
library;

/// Where a field's current value came from. Drives the origin badge in the
/// preview and the default merge decision — a value the model guessed should
/// not silently overwrite one a human (or another scraper) already wrote.
enum FieldOrigin {
  /// JSON-LD / OpenGraph on the page itself.
  structuredData,

  /// A cached or built-in CSS-selector recipe.
  recipe,

  /// Inferred by the LLM.
  llm,

  /// Read back from an NFO already on disk.
  existingNfo,

  /// Typed by the user in the preview.
  manual,

  /// Computed from another field (e.g. series from a product code prefix).
  derived,

  /// Combined from existing and scraped values during a merge decision.
  merged,
}

/// Canonical field keys. Used for [MediaMetadata.origins], for recipe
/// `labelMap` targets, and as the row identity in the merge UI, so the three
/// never drift apart. Anything not listed here is not writable by a recipe.
class MetadataField {
  static const title = 'title';
  static const originalTitle = 'originalTitle';
  static const sortTitle = 'sortTitle';
  static const code = 'code';
  static const plot = 'plot';
  static const outline = 'outline';
  static const tagline = 'tagline';
  static const premiered = 'premiered';
  static const runtimeMinutes = 'runtimeMinutes';
  static const studio = 'studio';
  static const series = 'series';
  static const director = 'director';
  static const rating = 'rating';
  static const genres = 'genres';
  static const tags = 'tags';
  static const actors = 'actors';
  static const poster = 'poster';
  static const fanart = 'fanart';
  static const extraFanart = 'extraFanart';

  /// Every key above, in the order the preview should show them.
  static const all = <String>[
    title,
    originalTitle,
    sortTitle,
    code,
    plot,
    outline,
    tagline,
    premiered,
    runtimeMinutes,
    studio,
    series,
    director,
    rating,
    genres,
    tags,
    actors,
    poster,
    fanart,
    extraFanart,
  ];

  /// Fields whose value is a list, so the merge UI can offer "merge" as a
  /// third option next to keep/replace.
  static const listFields = <String>{genres, tags, actors, extraFanart};
}

/// One credited person.
class MetadataActor {
  final String name;
  final String? role;
  final String? thumbUrl;

  const MetadataActor({required this.name, this.role, this.thumbUrl});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (role != null) 'role': role,
    if (thumbUrl != null) 'thumb': thumbUrl,
  };

  factory MetadataActor.fromJson(Map<String, dynamic> json) => MetadataActor(
    name: (json['name'] as String?)?.trim() ?? '',
    role: (json['role'] as String?)?.trim(),
    thumbUrl: (json['thumb'] as String?)?.trim(),
  );

  @override
  bool operator ==(Object other) =>
      other is MetadataActor && other.name == name && other.role == role;

  @override
  int get hashCode => Object.hash(name, role);

  @override
  String toString() => role == null ? name : '$name ($role)';
}

/// A scraped (or read-back) description of one title.
class MediaMetadata {
  String? title;
  String? originalTitle;
  String? sortTitle;

  /// Product / catalogue number. Becomes `<uniqueid>` and usually the sort
  /// title too.
  String? code;

  String? plot;

  /// Short blurb. We put marketing copy (e.g. a director's comment) here
  /// rather than in [plot], which should stay the actual synopsis.
  String? outline;
  String? tagline;

  /// ISO `yyyy-MM-dd`.
  String? premiered;
  int? runtimeMinutes;
  String? studio;
  String? series;
  String? director;
  double? rating;

  List<String> genres;
  List<String> tags;
  List<MetadataActor> actors;

  String? posterUrl;
  String? fanartUrl;
  List<String> extraFanartUrls;

  /// The page this came from. Written into the NFO as a comment so a later
  /// re-scrape (or a confused human) can find the source again.
  String? sourceUrl;

  final Map<String, FieldOrigin> origins;

  MediaMetadata({
    this.title,
    this.originalTitle,
    this.sortTitle,
    this.code,
    this.plot,
    this.outline,
    this.tagline,
    this.premiered,
    this.runtimeMinutes,
    this.studio,
    this.series,
    this.director,
    this.rating,
    List<String>? genres,
    List<String>? tags,
    List<MetadataActor>? actors,
    this.posterUrl,
    this.fanartUrl,
    List<String>? extraFanartUrls,
    this.sourceUrl,
    Map<String, FieldOrigin>? origins,
  }) : genres = genres ?? <String>[],
       tags = tags ?? <String>[],
       actors = actors ?? <MetadataActor>[],
       extraFanartUrls = extraFanartUrls ?? <String>[],
       origins = origins ?? <String, FieldOrigin>{};

  /// Year derived from [premiered]; null when the date is missing or malformed.
  int? get year {
    final p = premiered;
    if (p == null || p.length < 4) return null;
    return int.tryParse(p.substring(0, 4));
  }

  /// True when nothing worth writing was found. The scrape service treats this
  /// as a failure and falls through to the next tier.
  bool get isEmpty =>
      (title == null || title!.isEmpty) &&
      (code == null || code!.isEmpty) &&
      (plot == null || plot!.isEmpty) &&
      posterUrl == null &&
      genres.isEmpty &&
      actors.isEmpty;

  /// Reads one field by its [MetadataField] key. Returns `String`, `int`,
  /// `double`, `List<String>` or `List<MetadataActor>` depending on the field.
  Object? get(String field) => switch (field) {
    MetadataField.title => title,
    MetadataField.originalTitle => originalTitle,
    MetadataField.sortTitle => sortTitle,
    MetadataField.code => code,
    MetadataField.plot => plot,
    MetadataField.outline => outline,
    MetadataField.tagline => tagline,
    MetadataField.premiered => premiered,
    MetadataField.runtimeMinutes => runtimeMinutes,
    MetadataField.studio => studio,
    MetadataField.series => series,
    MetadataField.director => director,
    MetadataField.rating => rating,
    MetadataField.genres => genres,
    MetadataField.tags => tags,
    MetadataField.actors => actors,
    MetadataField.poster => posterUrl,
    MetadataField.fanart => fanartUrl,
    MetadataField.extraFanart => extraFanartUrls,
    _ => null,
  };

  /// Writes one field by its [MetadataField] key and records [origin].
  ///
  /// Values are coerced defensively because they arrive from JSON, from a
  /// recipe transform, or from an LLM — anything that cannot be coerced (or
  /// coerces to blank) is **dropped, leaving the previous value intact**,
  /// so one bad field never kills a whole scrape or wipes a good earlier tier.
  void set(String field, Object? value, FieldOrigin origin) {
    if (value == null) return;
    if (!_assign(field, value)) return;
    origins[field] = origin;
  }

  /// Field key -> setter, split by value type. A map beats a 19-arm switch
  /// here because every arm would otherwise repeat the same
  /// coerce/reject/assign dance.
  late final Map<String, void Function(String)> _stringSetters = {
    MetadataField.title: (v) => title = v,
    MetadataField.originalTitle: (v) => originalTitle = v,
    MetadataField.sortTitle: (v) => sortTitle = v,
    MetadataField.code: (v) => code = v,
    MetadataField.plot: (v) => plot = v,
    MetadataField.outline: (v) => outline = v,
    MetadataField.tagline: (v) => tagline = v,
    MetadataField.premiered: (v) => premiered = v,
    MetadataField.studio: (v) => studio = v,
    MetadataField.series: (v) => series = v,
    MetadataField.director: (v) => director = v,
    MetadataField.poster: (v) => posterUrl = v,
    MetadataField.fanart: (v) => fanartUrl = v,
  };

  late final Map<String, void Function(List<String>)> _listSetters = {
    MetadataField.genres: (v) => genres = v,
    MetadataField.tags: (v) => tags = v,
    MetadataField.extraFanart: (v) => extraFanartUrls = v,
  };

  bool _assign(String field, Object value) {
    final setString = _stringSetters[field];
    if (setString != null) {
      final v = _str(value);
      if (v == null) return false;
      setString(v);
      return true;
    }
    final setList = _listSetters[field];
    if (setList != null) {
      final v = _strList(value);
      if (v.isEmpty) return false;
      setList(v);
      return true;
    }
    if (field == MetadataField.actors) {
      final v = _actorList(value);
      if (v.isEmpty) return false;
      actors = v;
      return true;
    }
    if (field == MetadataField.runtimeMinutes) {
      final v = _int(value);
      if (v == null || v <= 0) return false;
      runtimeMinutes = v;
      return true;
    }
    if (field == MetadataField.rating) {
      final v = _double(value);
      if (v == null) return false;
      rating = v;
      return true;
    }
    return false; // unknown key: ignore rather than crash on a bad recipe
  }

  /// True when [field] currently holds nothing (null, empty string, empty list).
  bool isBlank(String field) {
    final v = get(field);
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is List) return v.isEmpty;
    return false;
  }

  static String? _str(Object v) {
    final s = v is String ? v : v.toString();
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static int? _int(Object v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().trim());
  }

  static double? _double(Object v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static List<String> _strList(Object v) {
    final raw = v is List ? v : [v];
    final out = <String>[];
    for (final e in raw) {
      final s = e?.toString().trim() ?? '';
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    return out;
  }

  static List<MetadataActor> _actorList(Object v) {
    final raw = v is List ? v : [v];
    final out = <MetadataActor>[];
    for (final e in raw) {
      if (e == null) continue;
      final a = e is MetadataActor
          ? e
          : e is Map<String, dynamic>
          ? MetadataActor.fromJson(e)
          : MetadataActor(name: e.toString().trim());
      if (a.name.isEmpty || out.contains(a)) continue;
      out.add(a);
    }
    return out;
  }

  MediaMetadata copy() => MediaMetadata(
    title: title,
    originalTitle: originalTitle,
    sortTitle: sortTitle,
    code: code,
    plot: plot,
    outline: outline,
    tagline: tagline,
    premiered: premiered,
    runtimeMinutes: runtimeMinutes,
    studio: studio,
    series: series,
    director: director,
    rating: rating,
    genres: List.of(genres),
    tags: List.of(tags),
    actors: List.of(actors),
    posterUrl: posterUrl,
    fanartUrl: fanartUrl,
    extraFanartUrls: List.of(extraFanartUrls),
    sourceUrl: sourceUrl,
    origins: Map.of(origins),
  );

  /// Copies every non-blank field of [other] into this one, recording origins.
  /// Used to layer a recipe result on top of a structured-data result.
  void fillFrom(MediaMetadata other, {bool overwrite = false}) {
    for (final f in MetadataField.all) {
      if (other.isBlank(f)) continue;
      if (!overwrite && !isBlank(f)) continue;
      set(f, other.get(f), other.origins[f] ?? FieldOrigin.recipe);
    }
    sourceUrl ??= other.sourceUrl;
  }
}
