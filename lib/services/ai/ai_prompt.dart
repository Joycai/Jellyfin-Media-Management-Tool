import 'dart:convert';

import 'ai_provider.dart';
import 'token_budget.dart';

/// One file handed to the model as context.
class MediaEntryInput {
  /// Name relative to the folder being organized (the model echoes this back
  /// as the action `source`, so it must round-trip exactly).
  final String relativePath;
  final int sizeBytes;

  /// Coarse kind from `FileLabelService` (Video / Subtitle / Image / …).
  final String kind;

  const MediaEntryInput({
    required this.relativePath,
    required this.sizeBytes,
    required this.kind,
  });
}

/// Builds the prompts that drive folder organization. Pure/static so it can be
/// unit-tested without any provider.
class AiPrompt {
  static const String systemPrompt = '''
You are a media-library organizer for Jellyfin. Given the files inside a single
folder, decide how to rename and move them so they follow Jellyfin's official
naming conventions, then return a JSON plan.

Jellyfin conventions to follow:
- Movies: "Movies/<Title> (<Year>)/<Title> (<Year>).<ext>". Keep edition tags in
  brackets when present, e.g. "Dune (2021) [Bluray-1080p].mkv".
- TV: "Shows/<Series> (<Year>)/Season <NN>/<Series> SxxEyy.<ext>".
- Subtitles sit next to their video and carry a language tag, e.g.
  "<VideoBaseName>.zh-Hans.ass" or ".en.srt". Mark forced/default when obvious.
- Posters/artwork: "poster.jpg", "fanart.jpg", "banner.jpg" in the title folder.
- Metadata: a movie's metadata file becomes "movie.nfo"; an episode's keeps its
  episode base name; a series uses "tvshow.nfo".
- Extras: "-featurette", "-interview", "-trailer", "-deleted", "-behindthescenes"
  suffixes, or a matching "Extras/" / "Featurettes/" subfolder.

Rules:
- Use the exact "source" string you were given for each file; do not invent files.
- "target" is a path RELATIVE to the library root you chose (the first segment is
  the root, e.g. "Movies/..."). Use forward slashes.
- Infer the title/year/season/episode from filenames; do not fabricate metadata
  you cannot derive. When unsure, lower the confidence and explain in "note".
- "confidence" is a number from 0 to 1.
- Output ONLY a single JSON object, no markdown fences or prose.

Respond with this exact shape:
{
  "mediaType": "movie | series | music | mixed | unknown",
  "targetRoot": "Movies",
  "reasoning": ["short step", "short step"],
  "actions": [
    {
      "source": "Dune.Part.Two.2024.2160p.mkv",
      "target": "Movies/Dune Part Two (2024)/Dune Part Two (2024).mkv",
      "kind": "video | subtitle | image | metadata | audio | extra | other",
      "confidence": 0.96,
      "note": "Detected film, matched year 2024"
    }
  ]
}
''';

  /// Serializes the folder context into the user message.
  ///
  /// [mediaTypeHint] is `"movie"`, `"series"`, or null. When set, the user is
  /// telling the model the folder's media type — the model should trust it
  /// instead of inferring from filenames, and set `mediaType` in the response
  /// accordingly. [titleHint], when non-empty, is the canonical movie/series
  /// title the model should use.
  ///
  /// [knownFolders] is set on every batch after the first when a folder is
  /// sent in pieces (see [batchEntries]): the title folders earlier batches
  /// chose, so one series is not filed under two spellings.
  static String buildUserPrompt({
    required String folderName,
    required List<MediaEntryInput> entries,
    String? titleHint,
    String? mediaTypeHint,
    List<String> knownFolders = const [],
  }) {
    final hint = titleHint?.trim();
    final type = mediaTypeHint?.trim();
    final payload = <String, Object>{
      'folder': folderName,
      if (type != null && type.isNotEmpty) 'userMediaType': type,
      if (hint != null && hint.isNotEmpty) 'userTitleHint': hint,
      'files': [
        for (final e in entries)
          {'source': e.relativePath, 'kind': e.kind, 'size': e.sizeBytes},
      ],
    };

    final parts = <String>[
      'Organize this folder into a Jellyfin-conform structure.',
    ];
    if (type == 'movie') {
      parts.add(
        'The user has confirmed this folder is a MOVIE — set "mediaType" to '
        '"movie" and use the Movies/ target root. Do not classify any item as '
        'an episode.',
      );
    } else if (type == 'series') {
      parts.add(
        'The user has confirmed this folder is a TV SERIES — set "mediaType" '
        'to "series" and use the Shows/ target root. Detect season and '
        'episode numbers per video file.',
      );
    }
    if (hint != null && hint.isNotEmpty) {
      parts.add(
        'The user says the title is "$hint" — trust that over filename '
        'guesswork, but still infer the year and season/episode numbers '
        'from the files.',
      );
    }
    if (knownFolders.isNotEmpty) {
      parts.add(
        'This folder is being organized in several batches. Earlier batches '
        'already placed files under '
        '${knownFolders.map((f) => '"$f"').join(', ')} — reuse those exact '
        'folder names for files that belong to the same title.',
      );
    }

    return '${parts.join(' ')}\n'
        '${const JsonEncoder.withIndent('  ').convert(payload)}';
  }

  /// Output tokens a plan spends on its framing — mediaType, targetRoot and
  /// the reasoning list — before any action.
  static const int _planOverhead = 300;

  /// Input tokens held back for the [knownFolders] line later batches carry.
  static const int _folderHintReserve = 200;

  /// Splits [entries] into batches whose requests fit [config]'s token budget.
  ///
  /// A plan costs more coming back than going out: every file returns as an
  /// action that restates its path and adds a target, a kind, a confidence
  /// and a note. So each file is charged for its line in the prompt *and* its
  /// action in the reply, and a batch closes when the context window — or, on
  /// its own, the output cap — would be exceeded.
  ///
  /// With neither limit set this is [entries] as one batch: exactly the single
  /// request the pipeline always sent.
  static List<List<MediaEntryInput>> batchEntries(
    List<MediaEntryInput> entries, {
    required AiConfig config,
    required String folderName,
    String? titleHint,
    String? mediaTypeHint,
  }) {
    final window = config.contextWindow;
    final maxOutput = config.maxOutputTokens;
    if (window == null && maxOutput == null) return [entries];

    final fixed =
        TokenBudget.estimate(systemPrompt) +
        TokenBudget.estimate(
          buildUserPrompt(
            folderName: folderName,
            entries: const [],
            titleHint: titleHint,
            mediaTypeHint: mediaTypeHint,
          ),
        ) +
        TokenBudget.templateOverhead +
        _folderHintReserve +
        _planOverhead;
    final windowBudget = window == null ? null : (window * 0.9).floor() - fixed;
    final outputBudget = maxOutput == null ? null : maxOutput - _planOverhead;

    final batches = <List<MediaEntryInput>>[];
    var batch = <MediaEntryInput>[];
    var total = 0;
    var output = 0;
    for (final entry in entries) {
      final reply = _actionCost(entry);
      final cost = _entryCost(entry) + reply;
      final fits =
          (windowBudget == null || total + cost <= windowBudget) &&
          (outputBudget == null || output + reply <= outputBudget);
      // A file too large to fit even alone still goes, on its own: sending it
      // is the only way to find out, and dropping it would silently leave it
      // out of the plan.
      if (!fits && batch.isNotEmpty) {
        batches.add(batch);
        batch = [];
        total = 0;
        output = 0;
      }
      batch.add(entry);
      total += cost;
      output += reply;
    }
    if (batch.isNotEmpty) batches.add(batch);
    return batches;
  }

  /// A file's line in the prompt: its JSON object plus indentation.
  static int _entryCost(MediaEntryInput e) =>
      TokenBudget.estimate(
        jsonEncode({
          'source': e.relativePath,
          'kind': e.kind,
          'size': e.sizeBytes,
        }),
      ) +
      8;

  /// A file's action in the reply: source and target each restate the path
  /// (the target adds a title folder), and kind, confidence and note add a
  /// steady sixty or so.
  static int _actionCost(MediaEntryInput e) =>
      2 * TokenBudget.estimate(e.relativePath) + 60;

  /// The title folders (`Shows/Breaking Bad (2008)`) that [targets] use: the
  /// library root plus the first folder under it. Capped, because the hint is
  /// there to pin spellings, not to restate the plan.
  static List<String> titleFolders(Iterable<String> targets, {int limit = 12}) {
    final folders = <String>{};
    for (final target in targets) {
      final segments = target
          .split(RegExp(r'[/\\]'))
          .where((s) => s.isNotEmpty)
          .toList();
      // Root, title folder, and something inside it.
      if (segments.length < 3) continue;
      folders.add('${segments[0]}/${segments[1]}');
      if (folders.length >= limit) break;
    }
    return folders.toList();
  }
}
