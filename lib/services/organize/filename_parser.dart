import 'package:path/path.dart' as p;

import '../file_label_service.dart';

/// What [FilenameParser] could read out of one file's relative path.
///
/// Every field is a guess from the name alone. It exists so code can do the
/// mechanical half of organizing — grouping episodes, numbering targets — and
/// leave only "which title is this" to the model, which small local models get
/// right far more often than a per-file move plan.
class ParsedFile {
  const ParsedFile({
    required this.relativePath,
    required this.folder,
    required this.baseName,
    required this.extension,
    required this.kind,
    this.season,
    this.episode,
    this.episodeEnd,
    this.year,
    this.part,
    this.special = false,
    this.extraType,
    this.language,
    this.specialLabel,
    required this.seriesKey,
    required this.titleGuess,
  });

  /// Exactly as given, platform separators included.
  final String relativePath;

  /// Containing folder, `''` at the root.
  final String folder;

  /// File name without its extension.
  final String baseName;

  /// Lowercase with the leading dot (`.mkv`), `''` when there is none.
  final String extension;

  /// [FileLabelService.getLabel] of [extension]: `Video`, `Subtitle`, `Image`,
  /// `Metadata`, `Audio`, `Text` or `Other`.
  final String kind;

  final int? season;
  final int? episode;

  /// Last episode of a multi-episode file (`S01E01-E02`), else null.
  final int? episodeEnd;

  final int? year;

  /// `cd1` / `part2` / `disc1`.
  final int? part;

  /// OVA, OAD, SP, Special(s), 特别篇 / 番外, or a file inside a `Specials`
  /// folder.
  final bool special;

  /// The Jellyfin extras folder this file belongs in (`trailers`,
  /// `deleted scenes`, `extras`, …), or null for main content.
  final String? extraType;

  /// `zh-Hans`, `zh-Hant`, `zh`, `ja`, `en`, `ko`, or another lowercase ISO 639
  /// code. Only subtitles and audio tracks need it, but it is recorded wherever
  /// the name states one.
  final String? language;

  /// The name a special Jellyfin cannot number goes under: a half episode's
  /// number and whatever the release says about it
  /// (`18.5 Collabo Detective Conan-20060606`). Jellyfin reads `S01E18.5` as a
  /// second episode 18, so a file with a label has no [episode] at all.
  final String? specialLabel;

  /// Equality key for "same title": case, punctuation, release tags and episode
  /// numbers removed. Never shown to anyone. `folder:<folder>` when the name
  /// carries no title at all, so bare `01.mkv` files still group together.
  final String seriesKey;

  /// Human-readable title in its original case, `''` when there is none.
  final String titleGuess;

  bool get isVideo => kind == 'Video';

  @override
  String toString() =>
      'ParsedFile($relativePath, title: "$titleGuess", key: "$seriesKey", '
      'S$season E$episode${episodeEnd == null ? '' : '-$episodeEnd'}, '
      'year: $year, part: $part, special: $special, extra: $extraType, '
      'language: $language, specialLabel: $specialLabel)';
}

/// Reads season / episode / year / part / extra / language out of media file
/// names as they come from release groups, rippers and hand-named libraries.
///
/// The approach is to find every *marker* (an episode token, a year, a
/// resolution, a codec…) and take the title from the text before the earliest
/// one. Removing tokens instead would leave episode names in the title
/// (`Show - 01 - Pilot`), and those differ per file, which is precisely what
/// must not split a show into one group per episode.
abstract final class FilenameParser {
  // Bracket and parenthesis pairs are rewritten to these before matching, so a
  // `(?<![A-Za-z0-9])` boundary treats them like separators and a group's extent
  // survives the rewrite. Neither can occur in a file name.
  static final _open = String.fromCharCode(2);
  static final _close = String.fromCharCode(3);

  // Everything below is compiled once. `parse` runs per file, `_cleanTitle`
  // per title, and one of these is applied per *word* -- so a RegExp literal
  // left inside any of them is a compilation per call, which for one organize
  // run over a large library is tens of thousands of compilations of the same
  // handful of patterns. The rest of this file already declares its patterns
  // as static finals; these were the ones inside method bodies.

  /// Audio channel layouts (`DTS-5.1`, `AAC2.0`), matched before dots turn
  /// into spaces.
  static final _audioLayout = RegExp(
    r'(?<=^|[\s._\-\[(A-Za-z])[2-9]\.[0-2](?=$|[\s._\-\])])',
  );

  /// Every opening-bracket style, rewritten to [_open].
  static final _anyOpenBracket = RegExp(r'[\[【(（]');

  /// Every closing-bracket style, rewritten to [_close].
  static final _anyCloseBracket = RegExp(r'[\]】)）]');

  /// Dot and ideographic-space separators.
  static final _dotSeparator = RegExp(r'[._　]');

  /// One normalized bracket group, capturing its contents. [parse] uses the
  /// capture; `_cleanTitle` uses the same pattern to strip groups, where the
  /// whole match is what gets replaced and the capture is ignored.
  static final _bracketGroup = RegExp('$_open([^$_close]*)(?:$_close|\$)');

  /// The bracket sentinels themselves, left behind once groups are stripped.
  static final _bracketSentinel = RegExp('[$_open$_close]');

  static final _whitespaceRun = RegExp(r'\s+');

  /// A word made only of punctuation, which carries no title information.
  static final _punctuationOnly = RegExp(r'^[-~–—:,;|+]+$');

  static final _firstNonSpace = RegExp(r'\S');

  /// A candidate title made only of digits is an episode number, not a title.
  static final _digitsOnly = RegExp(r'^\d+$');

  /// `chs&jpn`, `sc+jp`, `chs_jpn`: separators inside a language tail.
  static final _languageSeparators = RegExp(r'[&+_]');

  /// Separators inside a bracket group when hunting for a language token.
  static final _tokenSeparators = RegExp(r'[\s_&+,/]+');

  /// Punctuation at either edge of a cleaned title.
  static final _edgePunctuation = RegExp(r'^[-~–—:,;|]+|[-~–—:,;|]+$');

  /// Anything that is not a letter or a number, in any script.
  static final _nonAlphanumeric = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Full-width digits, folded to ASCII before `int.parse` sees them.
  static final _fullWidthDigits = RegExp('[０-９]');

  static ParsedFile parse(String relativePath) {
    final dir = p.dirname(relativePath);
    final folder = dir == '.' ? '' : dir;
    final extension = p.extension(relativePath).toLowerCase();
    final baseName = p.basenameWithoutExtension(relativePath);
    final kind = FileLabelService.getLabel(extension);

    var stem = baseName;
    String? language;
    // Dotted language tails (`Show - 01.chs.ass`) are a subtitle convention; on
    // a video the same position holds release tags, where `.WEB` or `.It`
    // would read as a language.
    if (kind != 'Video') {
      final tail = _stripLanguageTail(stem);
      stem = tail.$1;
      language = tail.$2;
    }

    String? extraType;
    final suffix = _extraSuffix.firstMatch(stem);
    if (suffix != null) {
      extraType = _suffixFolders[suffix.group(1)!.toLowerCase()];
      stem = stem.substring(0, suffix.start);
    }

    final text = _normalize(stem);
    final groups = [
      for (final m in _bracketGroup.allMatches(text))
        (start: m.start, end: m.end, content: m.group(1)!),
    ];

    // A bracket group at the very start is the release group in practice
    // (`[SubsPlease]`, `[VCB-Studio]`); markers inside it describe nothing.
    var leadEnd = 0;
    final first = text.indexOf(_firstNonSpace);
    if (first >= 0 && text[first] == _open) {
      final close = text.indexOf(_close, first);
      leadEnd = close < 0 ? text.length : close + 1;
    }

    int? season, episode, episodeEnd, year, part;
    var special = false;
    var cut = text.length;
    final taken = <(int, int)>[];

    void take(int start, int end) {
      taken.add((start, end));
      if (start < cut) cut = start;
    }

    bool overlapsTaken(int start, int end) =>
        taken.any((t) => start < t.$2 && t.$1 < end);

    Iterable<RegExpMatch> hits(RegExp re) =>
        re.allMatches(text).where((m) => m.start >= leadEnd);

    // Is there any real text before [index], outside bracket groups?
    bool textBefore(int index) =>
        _cleanTitle(text.substring(leadEnd, index)).isNotEmpty;

    for (final m in hits(_sxe)) {
      take(m.start, m.end);
      if (episode != null) continue;
      season = int.parse(m.group(1)!);
      episode = int.parse(m.group(2)!);
      episodeEnd = _end(episode, m.group(3) ?? m.group(4));
    }
    for (final m in hits(_cross)) {
      take(m.start, m.end);
      if (episode != null) continue;
      season = int.parse(m.group(1)!);
      episode = int.parse(m.group(2)!);
    }
    for (final re in _seasonMarkers) {
      for (final m in hits(re)) {
        if (overlapsTaken(m.start, m.end)) continue;
        take(m.start, m.end);
        season ??= _number(m.group(1)!);
      }
    }
    for (final m in hits(_episodeMarker)) {
      if (overlapsTaken(m.start, m.end)) continue;
      take(m.start, m.end);
      if (episode != null) continue;
      episode = int.parse(m.group(1) ?? m.group(2)!);
      episodeEnd = _end(episode, m.group(3));
    }
    for (final m in hits(_cjkEpisodeMarker)) {
      if (overlapsTaken(m.start, m.end)) continue;
      take(m.start, m.end);
      if (episode != null) continue;
      episode = _number(m.group(1)!);
      if (episode != null) episodeEnd = _end(episode, m.group(2));
    }

    // A half episode (`[18.5]`, `- 18.5`) is a special in all but name.
    // Jellyfin reads `S01E18.5` as a second episode 18, so it gets no episode
    // number; [ParsedFile.specialLabel] names it instead.
    String? fractional;
    var fractionalEnd = 0;
    if (episode == null) {
      for (final g in groups) {
        if (g.start < leadEnd || overlapsTaken(g.start, g.end)) continue;
        final m = _fractionalBracket.firstMatch(g.content.trim());
        if (m == null) continue;
        take(g.start, g.end);
        fractional = m.group(1)!;
        fractionalEnd = g.end;
        break;
      }
    }
    if (episode == null && fractional == null) {
      for (final m in hits(_fractionalDash)) {
        if (overlapsTaken(m.start, m.end)) continue;
        take(m.start, m.end);
        fractional = m.group(1)!;
        fractionalEnd = m.end;
        break;
      }
    }
    if (fractional != null) special = true;

    for (final re in _specialMarkers) {
      for (final m in hits(re)) {
        if (overlapsTaken(m.start, m.end)) continue;
        take(m.start, m.end);
        special = true;
        final number = m.groupCount > 0 ? m.group(1) : null;
        if (episode == null && number != null) episode = int.parse(number);
      }
    }
    // "Special" is also an ordinary English word, so it only counts where a
    // release would put it: after a dash, with a number, or at the very end.
    for (final m in hits(_specialWord)) {
      if (overlapsTaken(m.start, m.end)) continue;
      final before = text.substring(0, m.start).trimRight();
      final counts =
          m.group(1) != null ||
          before.endsWith('-') ||
          before.endsWith(_open) ||
          _onlyGroupsLeft.hasMatch(text.substring(m.end));
      if (!counts) continue;
      take(m.start, m.end);
      special = true;
      if (episode == null && m.group(1) != null) {
        episode = int.parse(m.group(1)!);
      }
    }

    for (final re in _animeExtraMarkers) {
      for (final m in hits(re)) {
        if (overlapsTaken(m.start, m.end)) continue;
        take(m.start, m.end);
        extraType ??= 'extras';
      }
    }

    for (final re in _partMarkers) {
      for (final m in hits(re)) {
        if (overlapsTaken(m.start, m.end)) continue;
        take(m.start, m.end);
        part ??= int.parse(m.group(1)!);
      }
    }

    var enclosedYear = false;
    for (final g in groups) {
      if (g.start < leadEnd) continue;
      final m = _yearOnly.firstMatch(g.content);
      if (m == null) continue;
      take(g.start, g.end);
      if (year == null) {
        year = int.parse(m.group(1)!);
        enclosedYear = true;
      }
    }
    // A parenthesized year is how Jellyfin itself names titles, so it outranks
    // any bare one — `Blade Runner 2049 (2017)` must not become 2049. Without
    // one, the last bare year wins: `2001 A Space Odyssey 1968` has a title
    // that starts with one.
    if (year == null) {
      RegExpMatch? chosen;
      for (final m in hits(_bareYear)) {
        if (overlapsTaken(m.start, m.end) || !textBefore(m.start)) continue;
        chosen = m;
      }
      if (chosen != null) {
        take(chosen.start, chosen.end);
        year = int.parse(chosen.group(1)!);
      }
    }

    for (final re in _techMarkers) {
      for (final m in hits(re)) {
        if (!overlapsTaken(m.start, m.end)) take(m.start, m.end);
      }
    }

    // Bare numbers last: they are the weakest evidence of an episode, and
    // everything that could look like one (years, 1080p, x264, SP01) has
    // claimed its span by now.
    if (episode == null && fractional == null) {
      for (final m in hits(_dashEpisode)) {
        final raw = m.group(1)!;
        if (overlapsTaken(m.start, m.end) || _isYear(raw)) continue;
        take(m.start, m.end);
        episode = int.parse(raw);
        episodeEnd = _end(episode, m.group(2));
        break;
      }
    }
    if (episode == null && fractional == null) {
      for (final g in groups) {
        if (g.start < leadEnd || overlapsTaken(g.start, g.end)) continue;
        final m = _bracketEpisode.firstMatch(g.content.trim());
        if (m == null) continue;
        final raw = m.group(1)!;
        if (_isYear(raw) || _resolutions.contains(int.parse(raw))) continue;
        take(g.start, g.end);
        episode = int.parse(raw);
        episodeEnd = _end(episode, m.group(2));
        break;
      }
    }
    // A trailing number (`Show 第二季 05`) is also how sequels are named, so it
    // needs two digits unless it is the whole name, and is not trusted at all
    // next to a Jellyfin-style `(year)` — `Ocean's 11 (2001)` is a movie.
    if (episode == null && fractional == null && !enclosedYear) {
      for (final m in hits(_trailingNumber)) {
        final raw = m.group(1)!;
        if (overlapsTaken(m.start, m.end) ||
            _isYear(raw) ||
            _resolutions.contains(int.parse(raw))) {
          continue;
        }
        if (raw.length < 2 && textBefore(m.start)) continue;
        take(m.start, m.end);
        episode = int.parse(raw);
        break;
      }
    }

    // What the release says about a half episode, kept as written: the plain
    // text right after its number and every later bracket no marker claimed.
    // A descriptive name is Jellyfin's own advice for a special its metadata
    // source does not know.
    String? specialLabel;
    if (fractional != null) {
      var until = text.length;
      for (final t in taken) {
        if (t.$1 >= fractionalEnd && t.$1 < until) until = t.$1;
      }
      for (final g in groups) {
        if (g.start >= fractionalEnd && g.start < until) until = g.start;
      }
      specialLabel = [
        fractional.replaceAll(_point, '.'),
        _cleanTitle(text.substring(fractionalEnd, until)),
        for (final g in groups)
          if (g.start >= fractionalEnd && !overlapsTaken(g.start, g.end))
            _cleanTitle(g.content),
      ].where((part) => part.isNotEmpty).join(' ');
    }

    var titleGuess = _cleanTitle(text.substring(0, cut), from: leadEnd);
    if (titleGuess.isEmpty) {
      // `[Group][Title][01][1080p]` keeps its title inside brackets.
      for (final g in groups) {
        if (g.start < leadEnd || g.end > cut) continue;
        final candidate = _cleanTitle(g.content);
        if (candidate.isNotEmpty && !_digitsOnly.hasMatch(candidate)) {
          titleGuess = candidate;
          break;
        }
      }
    }

    language ??= _bracketLanguage(groups.where((g) => g.start >= leadEnd));
    if (language == null) {
      final outside = text.substring(leadEnd);
      final cjk = _cjkLanguageTag.firstMatch(outside);
      if (cjk != null) {
        language = cjk.group(0)!.startsWith('简') ? 'zh-Hans' : 'zh-Hant';
      } else {
        final latin = _latinLanguageTag.firstMatch(outside);
        if (latin != null) {
          language = _languageTags[latin.group(0)!.toLowerCase()];
        }
      }
    }

    final folderName = folder.isEmpty ? '' : p.basename(folder);
    season ??= _seasonOfFolder(folderName);
    if (_specialsFolder.hasMatch(folderName)) special = true;
    if (extraType == null && kind == 'Video') {
      extraType = _extrasFolders[folderName.toLowerCase()];
    }

    var seriesKey = _key(titleGuess);
    if (seriesKey.isEmpty) {
      final owner = containerParent(folder);
      seriesKey =
          'folder:${owner.isEmpty ? '' : p.split(owner).join('/').toLowerCase()}';
    }

    return ParsedFile(
      relativePath: relativePath,
      folder: folder,
      baseName: baseName,
      extension: extension,
      kind: kind,
      season: season,
      episode: episode,
      episodeEnd: episodeEnd,
      year: year,
      part: part,
      special: special,
      extraType: extraType,
      language: language,
      specialLabel: specialLabel,
      seriesKey: seriesKey,
      titleGuess: titleGuess,
    );
  }

  /// Whether a folder named [name] only subdivides a title (`Season 2`,
  /// `Specials`, `Extras`, `CD1`) rather than being one.
  static bool isContainerFolder(String name) {
    final lower = name.trim().toLowerCase();
    return _seasonOfFolder(name) != null ||
        _specialsFolder.hasMatch(lower) ||
        _extrasFolders.containsKey(lower) ||
        _discFolder.hasMatch(lower);
  }

  /// [folder] with trailing container folders removed: the folder that holds
  /// the title itself. `Show/Season 1` → `Show`; `''` at the root.
  static String containerParent(String folder) {
    if (folder.isEmpty) return '';
    final parts = p.split(folder);
    while (parts.isNotEmpty && isContainerFolder(parts.last)) {
      parts.removeLast();
    }
    return parts.isEmpty ? '' : p.joinAll(parts);
  }

  // ---------------------------------------------------------------- patterns

  static final _sxe = RegExp(
    r'(?<![A-Za-z0-9])S(\d{1,2})\s?E(\d{1,4})(?:-?E(\d{1,4})|-(\d{1,4}))?'
    r'(?:v\d{1,2})?(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static final _cross = RegExp(
    r'(?<![A-Za-z0-9])(\d{1,2})x(\d{2,3})(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static final _seasonMarkers = [
    RegExp(r'(?<![A-Za-z0-9])S(\d{1,2})(?![A-Za-z0-9])', caseSensitive: false),
    RegExp(
      r'(?<![A-Za-z0-9])Season\s?(\d{1,2})(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    RegExp(
      r'(?<![A-Za-z0-9])(\d{1,2})(?:st|nd|rd|th)\s+Season(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    RegExp(r'第\s*([0-9０-９一二两三四五六七八九十]+)\s*[季期]'),
  ];

  // `E01` needs two digits: a lone `E3` is more often part of a title.
  static final _episodeMarker = RegExp(
    r'(?<![A-Za-z0-9])(?:EP\s?(\d{1,4})|E(\d{2,4}))(?:-(?:EP?)?(\d{1,4}))?'
    r'(?:v\d{1,2})?(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static final _cjkEpisodeMarker = RegExp(
    r'第\s*([0-9０-９一二两三四五六七八九十百零〇]+)'
    r'(?:\s*[-~]\s*([0-9０-９]+))?\s*[话話集回]',
  );

  static final _specialMarkers = [
    RegExp(
      r'(?<![A-Za-z0-9])(?:OVA|OAD|OAV)(?:\s?(\d{1,3}))?(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    RegExp(
      r'(?<![A-Za-z0-9])SP\s?(\d{1,3})(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    // Bare lowercase "sp" is too common a fragment; only the uppercase tag.
    RegExp(r'(?<![A-Za-z0-9])SP(?![A-Za-z0-9])'),
    RegExp(r'(?:特别篇|特別篇|番外篇?)\s*(\d{1,3})?'),
  ];

  static final _specialWord = RegExp(
    r'(?<![A-Za-z0-9])Specials?(?:\s?(\d{1,3}))?(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  // Creditless openings/endings, promo videos, commercials and disc menus. PV
  // and CM are uppercase-only, and Menu needs a dash or bracket in front,
  // because `The Menu (2022)` is a film.
  static final _animeExtraMarkers = [
    RegExp(
      r'(?<![A-Za-z0-9])NC(?:OP|ED)\s?\d{0,2}(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    RegExp(r'(?<![A-Za-z0-9])(?:PV|CM)\s?\d{0,2}(?![A-Za-z0-9])'),
    RegExp(
      '(?:(?<=-\\s*)|(?<=$_open\\s*))Menu\\s?\\d{0,2}(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
  ];

  // `Part 1` as a free word is a real title (Deathly Hallows); only the glued
  // or dash-separated forms Jellyfin documents count.
  static final _partMarkers = [
    RegExp(
      r'(?<![A-Za-z0-9])(?:cd|dvd|dis[ck])\s?(\d{1,2})(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    RegExp(
      r'(?<![A-Za-z0-9])(?:part|pt)(\d{1,2})(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    RegExp(r'-\s*(?:part|pt)\s?(\d{1,2})(?![A-Za-z0-9])', caseSensitive: false),
  ];

  static final _yearOnly = RegExp(r'^\s*((?:19|20)\d{2})\s*$');
  static final _bareYear = RegExp(
    r'(?<![A-Za-z0-9])((?:19|20)\d{2})(?![A-Za-z0-9])',
  );

  static final _techMarkers = [
    RegExp(
      r'(?<![A-Za-z0-9])(?:\d{3,4}[pi]|[48]k|uhd|hdr(?:10\+?)?|dovi|x26[45]|'
      r'h\s?26[45]|hevc|avc|av1|xvid|divx|1[02]bits?|8bits?|hi10p?|ma10p|'
      r'web-?dl|web-?rip|blu-?ray|bdrip|brrip|bdremux|remux|hdtv|hdrip|dvdrip|'
      r'tvrip|aac|ac3|e-?ac-?3|ddp?|dts(?:-?hd)?(?:-?ma)?|truehd|atmos|flac|'
      r'opus|lpcm|mp3|proper|repack|amzn|dsnp|chs|cht|big5|multi-?subs?|'
      r'dual-?audio)(?![A-Za-z0-9])',
      caseSensitive: false,
    ),
    // Ordinary words in lowercase ("Charlotte's Web"), tags in uppercase.
    RegExp(r'(?<![A-Za-z0-9])(?:WEB|BD|DV|NF|GB)(?![A-Za-z0-9])'),
    RegExp(r'简体|简中|简日|简繁|繁体|繁體|繁中|繁日|繁简|双语|雙語|内封|內封|内嵌|內嵌|外挂|外掛'),
  ];

  static final _dashEpisode = RegExp(
    r'(?<=^|\s)-\s*(\d{1,4})(?:v\d{1,2})?(?:\s*-\s*(\d{1,4})(?:v\d{1,2})?)?'
    r'(?![A-Za-z0-9])',
  );

  /// Stands in for the point of a half episode (`18.5`) through [_normalize],
  /// which turns every other `.` into a word break.
  static final _point = String.fromCharCode(4);

  /// A half episode where a release puts an episode number: alone in a
  /// bracket, or after a dash. Only `.5` — `5.1` and `2.0` are audio layouts.
  static final _protectFractional = RegExp(
    r'(?<=[\[【(（]\s*)(\d{1,4})\.5(?=(?:v\d{1,2})?\s*[\]】)）])'
    r'|(?<=(?:^|[\s_])-[\s_]*)(\d{1,4})\.5(?=(?:v\d{1,2})?(?:$|[\s_\[【(（]))',
  );

  static final _fractionalBracket = RegExp(
    '^(\\d{1,4}${_point}5)(?:v\\d{1,2})?\$',
  );

  static final _fractionalDash = RegExp(
    '(?<=^|\\s)-\\s*(\\d{1,4}${_point}5)(?:v\\d{1,2})?(?![A-Za-z0-9])',
  );

  static final _bracketEpisode = RegExp(
    r'^(\d{1,4})(?:v\d{1,2})?(?:\s*-\s*(\d{1,4})(?:v\d{1,2})?)?'
    r'(?:\s*(?:end|fin))?$',
    caseSensitive: false,
  );

  static final _trailingNumber = RegExp(
    '(?<![A-Za-z0-9])(\\d{1,4})(?:v\\d{1,2})?'
    '(?=(?:\\s|$_open[^$_close]*$_close)*\$)',
  );

  static final _onlyGroupsLeft = RegExp(
    '^(?:\\s|$_open[^$_close]*(?:$_close|\$))*\$',
  );

  static const _resolutions = {480, 576, 720, 1080, 2160};

  // Jellyfin's documented extra suffixes. `trailer` alone also accepts a dot
  // or space, since nothing else is spelled that way.
  static final _extraSuffix = RegExp(
    r'(?:\s*-\s*|[\s._](?=trailer))(trailer|sample|scene|clip|interview|'
    r'behindthescenes|deletedscene|deleted|featurette|short|other|extra)\d*$',
    caseSensitive: false,
  );

  static const _suffixFolders = {
    'trailer': 'trailers',
    'sample': 'samples',
    'scene': 'scenes',
    'clip': 'clips',
    'interview': 'interviews',
    'behindthescenes': 'behind the scenes',
    'deletedscene': 'deleted scenes',
    'deleted': 'deleted scenes',
    'featurette': 'featurettes',
    'short': 'shorts',
    'other': 'other',
    'extra': 'extras',
  };

  // Folder names Jellyfin treats as extras. `other` and `samples` are left
  // out: as folder names they are too likely to be the user's own.
  static const _extrasFolders = {
    'extras': 'extras',
    'extra': 'extras',
    'trailers': 'trailers',
    'featurettes': 'featurettes',
    'interviews': 'interviews',
    'deleted scenes': 'deleted scenes',
    'behind the scenes': 'behind the scenes',
    'scenes': 'scenes',
    'shorts': 'shorts',
    'clips': 'clips',
  };

  static final _seasonFolder = RegExp(
    r'^(?:(?:season|series)[\s._-]*(\d{1,3})|s(\d{1,3}))$',
    caseSensitive: false,
  );
  static final _cjkSeasonFolder = RegExp(
    r'^第\s*([0-9０-９一二两三四五六七八九十]+)\s*[季期]$',
  );
  static final _specialsFolder = RegExp(
    r'^(?:specials?|sps?)$',
    caseSensitive: false,
  );
  static final _discFolder = RegExp(r'^(?:cds|(?:cd|dis[ck]|dvd)\s?\d{1,2})$');

  static const _languageTags = {
    'chs': 'zh-Hans',
    'sc': 'zh-Hans',
    'gb': 'zh-Hans',
    'zhs': 'zh-Hans',
    'zh-hans': 'zh-Hans',
    'zh-cn': 'zh-Hans',
    'zh-sg': 'zh-Hans',
    'cht': 'zh-Hant',
    'tc': 'zh-Hant',
    'big5': 'zh-Hant',
    'zht': 'zh-Hant',
    'zh-hant': 'zh-Hant',
    'zh-tw': 'zh-Hant',
    'zh-hk': 'zh-Hant',
    'zh': 'zh',
    'zho': 'zh',
    'chi': 'zh',
    'ja': 'ja',
    'jp': 'ja',
    'jpn': 'ja',
    'en': 'en',
    'eng': 'en',
    'ko': 'ko',
    'kor': 'ko',
    'kr': 'ko',
  };

  // Accepted only as a dotted subtitle tail. A closed list rather than "any
  // two or three letters", because `Movie.The.End.srt` ends in one too.
  static const _otherLanguages = {
    'ar', 'ara', 'cs', 'cze', 'ces', 'da', 'dan', 'de', 'ger', 'deu', //
    'el', 'gre', 'ell', 'es', 'spa', 'fi', 'fin', 'fr', 'fre', 'fra', //
    'he', 'heb', 'hi', 'hin', 'hu', 'hun', 'id', 'ind', 'it', 'ita', //
    'ms', 'msa', 'nl', 'dut', 'nld', 'no', 'nor', 'pl', 'pol', 'pt', //
    'por', 'ro', 'rum', 'ron', 'ru', 'rus', 'sv', 'swe', 'th', 'tha', //
    'tr', 'tur', 'uk', 'ukr', 'vi', 'vie',
  };

  static const _subtitleFlags = {'forced', 'default', 'foreign', 'sdh', 'cc'};

  static final _cjkLanguageTag = RegExp(r'简体|简中|简日|简繁|繁体|繁體|繁中|繁日|繁简');
  static final _latinLanguageTag = RegExp(
    r'(?<![A-Za-z0-9])(?:chs|cht|big5)(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  // ----------------------------------------------------------------- helpers

  static (String, String?) _stripLanguageTail(String stem) {
    final segments = stem.split('.');
    var keep = segments.length;
    String? language;
    while (keep > 1 && segments.length - keep < 3) {
      final segment = segments[keep - 1].toLowerCase();
      if (_subtitleFlags.contains(segment)) {
        keep--;
        continue;
      }
      final tag = _tailLanguage(segment);
      if (tag == null) break;
      language ??= tag;
      keep--;
    }
    return (segments.take(keep).join('.'), language);
  }

  static String? _tailLanguage(String segment) {
    final normalized = segment.replaceAll('_', '-');
    final known = _languageTags[normalized];
    if (known != null) return known;
    if (_otherLanguages.contains(normalized)) return normalized;
    // `chs&jpn`, `sc+jp`: the first language names the file.
    final parts = segment.split(_languageSeparators);
    if (parts.length > 1 && parts.every(_languageTags.containsKey)) {
      return _languageTags[parts.first];
    }
    return null;
  }

  static String? _bracketLanguage(
    Iterable<({int start, int end, String content})> groups,
  ) {
    for (final g in groups) {
      final cjk = _cjkLanguageTag.firstMatch(g.content);
      if (cjk != null) {
        return cjk.group(0)!.startsWith('简') ? 'zh-Hans' : 'zh-Hant';
      }
      final content = g.content.trim();
      if (content == '简') return 'zh-Hans';
      if (content == '繁') return 'zh-Hant';
      for (final token in content.toLowerCase().split(_tokenSeparators)) {
        final tag = _languageTags[token];
        if (tag != null) return tag;
      }
    }
    return null;
  }

  static String _normalize(String stem) => stem
      // Half episodes first, before their point becomes a word break.
      .replaceAllMapped(
        _protectFractional,
        (m) => '${m.group(1) ?? m.group(2)}${_point}5',
      )
      // Audio channel layouts (`DTS-5.1`, `AAC2.0`) before dots become
      // spaces, or `5.1` would read as two numbers.
      .replaceAll(_audioLayout, ' ')
      .replaceAll(_anyOpenBracket, _open)
      .replaceAll(_anyCloseBracket, _close)
      .replaceAll(_dotSeparator, ' ');

  static String _cleanTitle(String head, {int from = 0}) {
    final visible = from >= head.length ? '' : head.substring(from);
    final outside = visible
        .replaceAll(_bracketGroup, ' ')
        .replaceAll(_bracketSentinel, ' ');
    final words = outside
        .split(_whitespaceRun)
        .where((w) => w.isNotEmpty && !_punctuationOnly.hasMatch(w));
    return words.join(' ').replaceAll(_edgePunctuation, '').trim();
  }

  static String _key(String title) =>
      title.toLowerCase().replaceAll(_nonAlphanumeric, ' ').trim();

  static int? _seasonOfFolder(String name) {
    final m = _seasonFolder.firstMatch(name.trim());
    if (m != null) return int.parse(m.group(1) ?? m.group(2)!);
    final cjk = _cjkSeasonFolder.firstMatch(name.trim());
    return cjk == null ? null : _number(cjk.group(1)!);
  }

  static bool _isYear(String raw) {
    if (raw.length != 4) return false;
    final n = int.parse(raw);
    return n >= 1900 && n <= 2099;
  }

  static int? _end(int start, String? raw) {
    if (raw == null) return null;
    final end = _number(raw);
    return end != null && end > start ? end : null;
  }

  /// ASCII, full-width or Chinese numerals (`05`, `０５`, `二十三`).
  static int? _number(String raw) {
    final ascii = raw.replaceAllMapped(
      _fullWidthDigits,
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFF10 + 0x30),
    );
    final parsed = int.tryParse(ascii);
    if (parsed != null) return parsed;
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    var total = 0;
    var current = 0;
    for (final ch in raw.split('')) {
      final digit = digits[ch];
      if (digit != null) {
        current = digit;
      } else if (ch == '十' || ch == '百') {
        total += (current == 0 ? 1 : current) * (ch == '十' ? 10 : 100);
        current = 0;
      } else {
        return null;
      }
    }
    return total + current;
  }
}
