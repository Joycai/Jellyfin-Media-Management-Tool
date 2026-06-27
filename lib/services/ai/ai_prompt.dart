import 'dart:convert';

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
  static String buildUserPrompt({
    required String folderName,
    required List<MediaEntryInput> entries,
  }) {
    final payload = {
      'folder': folderName,
      'files': [
        for (final e in entries)
          {
            'source': e.relativePath,
            'kind': e.kind,
            'size': e.sizeBytes,
          }
      ],
    };
    return 'Organize this folder into a Jellyfin-conform structure.\n'
        '${const JsonEncoder.withIndent('  ').convert(payload)}';
  }
}
