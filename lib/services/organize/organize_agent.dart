/// Organizes one folder as a tool loop over groups of files.
///
/// Code does everything that has a right answer: parsing names, attaching an
/// episode's subtitles to it, spelling each Jellyfin path. The model answers
/// only what names cannot settle — what a group is called, film or show,
/// which year — once per group. A 26-episode series is one decision rather
/// than 26 paths to spell identically, and the paths a decision produces go
/// back to the model, so a wrong season is corrected before the user sees it.
///
/// The model never writes a path and never names a file by path: it points at
/// groups by id and files by number. Nothing it says can aim a move outside
/// the folder, and the preview remains the only gate to the disk.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../models/organize_plan.dart';
import '../agent/agent_runtime.dart';
import '../ai/ai_cancel_token.dart';
import '../ai/ai_provider.dart';
import '../metadata/nfo_reader.dart';
import 'filename_parser.dart';
import 'grouping.dart';
import 'jellyfin_naming.dart';

/// Reads a file inside the folder being organized by its relative path, or
/// returns null when it cannot.
typedef ReadFolderFile = Future<String?> Function(String relativePath);

class OrganizeRun {
  final OrganizePlan plan;

  /// Model requests made — zero when nothing needed deciding.
  final int rounds;

  const OrganizeRun({required this.plan, required this.rounds});
}

class OrganizeAgent {
  final AiProvider provider;

  /// Runs once before the first model call. `AiService` passes `ensureTools`,
  /// so a model that cannot call tools fails saying so.
  final Future<void> Function()? beforeStart;

  const OrganizeAgent(this.provider, {this.beforeStart});

  /// A look at the groups, a file listing and a decision per group, with
  /// slack for resubmissions — and a ceiling, so a model going in circles
  /// stops costing tokens.
  static int maxRoundsFor(int groups) => (6 + groups * 3).clamp(12, 200);

  /// Groups [files], has the model decide each group, and turns the decisions
  /// into a plan. A group the model did not decide still appears, with every
  /// file flagged for review, so nothing silently drops out of the preview.
  ///
  /// Throws [AiException] when the model decided nothing at all: a plan of
  /// nothing but flagged rows would only hide that the run failed.
  Future<OrganizeRun> run({
    required String folderName,
    required List<ParsedFile> files,
    String? titleHint,
    GroupMediaType? typeHint,
    ReadFolderFile? readFile,
    AiCancelToken? cancelToken,
    void Function(int resolved, int total)? onProgress,
  }) async {
    final state = OrganizeState(
      Grouping.build(files),
      typeHint: typeHint,
      readFile: readFile,
    );
    if (state.required.isEmpty) {
      return OrganizeRun(
        plan: state.buildPlan(promptTokens: 0, completionTokens: 0),
        rounds: 0,
      );
    }

    await beforeStart?.call();
    cancelToken?.throwIfCancelled();
    void report() => onProgress?.call(
      state.required.length - state.undecided.length,
      state.required.length,
    );
    report();

    final run = await AgentRuntime.run<OrganizeState>(
      provider: provider,
      messages: [
        const SystemMessage(systemPrompt),
        UserMessage(
          buildTaskPrompt(
            folderName: folderName,
            fileCount: files.length,
            groupCount: state.groups.length,
            undecided: state.undecided.length,
            titleHint: titleHint,
            typeHint: typeHint,
            firstPage: state.groupsPage(1),
          ),
        ),
      ],
      tools: const [
        _ListGroupsTool(),
        _ListGroupFilesTool(),
        _ReadExistingNfoTool(),
        _SubmitGroupTool(),
        _SplitGroupTool(),
        _MarkUnsureTool(),
      ],
      context: state,
      maxRounds: maxRoundsFor(state.required.length),
      isDone: () => state.undecided.isEmpty,
      nudge: () {
        final left = state.undecided;
        if (left.isEmpty) return null;
        final ids = left.take(12).map((g) => g.group.id).join(', ');
        return 'Still undecided: $ids${left.length > 12 ? ', …' : ''}. '
            'Call submit_group or mark_unsure for each of them.';
      },
      contextWindow: provider.config.contextWindow,
      cancelToken: cancelToken,
      onEvent: (event) {
        if (event is AgentToolFinished) report();
      },
    );

    if (state.required.every((g) => !g.resolved)) {
      throw AiException(switch (run.outcome) {
        AgentOutcome.erratic =>
          'The model kept calling the organize tools incorrectly and was '
              'stopped. Try a larger model, or turn thinking on.',
        AgentOutcome.exhausted =>
          'The model used all its rounds without deciding any group.',
        _ => 'The model stopped without deciding any group.',
      });
    }
    return OrganizeRun(
      plan: state.buildPlan(
        promptTokens: run.promptTokens,
        completionTokens: run.completionTokens,
      ),
      rounds: run.rounds,
    );
  }

  static const systemPrompt = '''
You organize a media folder for Jellyfin.

The app has already scanned the folder, parsed every file name and grouped the
files: a group is normally one movie or one show, with its subtitles, artwork
and NFO files attached. You decide what each group IS. The app builds every
file name and folder from your decision, so you never write paths.

Tools:
- list_groups: the groups, a page at a time, with sample names and what was
  parsed from them.
- list_group_files: every file in one group, numbered, with its parsed season,
  episode, year and language — and, once decided, the path it will get.
- read_existing_nfo: titles and years from NFO files already in a group.
- submit_group: your decision for one group. The reply shows the paths it
  produces and any file that could not be placed. Submitting a group again
  replaces your earlier decision.
- split_group: when a group mixes titles, move the files that do not belong
  into a new group, then decide both.
- mark_unsure: when you cannot tell what a group is. Its files are left for the
  user to review.

Every group that has videos needs submit_group or mark_unsure. When none is
left, reply in one short sentence without calling a tool.

How to decide:
- mediaType "series" when the videos are episodes, "movie" for one feature
  (possibly split into parts).
- title: the real title as the names, folder or NFO give it, in the same
  language and script. Remove release groups, resolutions, codecs and other
  tags. Do not translate. Do not invent a title nothing suggests.
- year: only when a name, the folder or an NFO states it. Otherwise omit it.
- season: only for files whose names carry no season, e.g. a folder named
  "Season 2" or "第二季". Omit it for season 1.
- episodeOffset: only when a later season continues the episode numbering
  (season 2 starting at episode 13 means -12). Usually omit it.
- Groups of the same show or movie must use the same title and year.
- confidence from 0 to 1. Below 0.6 the files are flagged for review.''';

  static String buildTaskPrompt({
    required String folderName,
    required int fileCount,
    required int groupCount,
    required int undecided,
    required String firstPage,
    String? titleHint,
    GroupMediaType? typeHint,
  }) {
    final title = titleHint?.trim() ?? '';
    return [
      'Folder: "$folderName"',
      '$fileCount file(s) in $groupCount group(s); $undecided group(s) with '
          'videos need a decision.',
      if (typeHint == GroupMediaType.movie)
        'The user says this folder holds MOVIES: use mediaType "movie".',
      if (typeHint == GroupMediaType.series)
        'The user says this folder holds a TV SERIES: use mediaType "series".',
      if (title.isNotEmpty)
        'The user gives the title "$title". Use it exactly as written for the '
            'groups it names — normally all of them.',
      '',
      firstPage,
    ].join('\n');
  }
}

/// One group and what has been decided about it.
class GroupState {
  MediaGroup group;
  GroupDecision? decision;
  double confidence = 0;
  String note = '';
  String? unsureReason;
  List<PlannedTarget> planned = const [];

  GroupState(this.group);

  bool get resolved => decision != null || unsureReason != null;

  void decide(GroupDecision value, double confidence, String note) {
    decision = value;
    this.confidence = confidence;
    this.note = note;
    unsureReason = null;
    planned = JellyfinNaming.plan(group, value);
  }

  void markUnsure(String reason) {
    decision = null;
    unsureReason = reason;
    planned = const [];
  }

  void reset(MediaGroup replacement) {
    group = replacement;
    decision = null;
    unsureReason = null;
    planned = const [];
  }
}

/// The task state the organize tools read and write.
class OrganizeState {
  final List<GroupState> groups;
  final GroupMediaType? typeHint;
  final ReadFolderFile? readFile;

  static const groupsPerPage = 20;
  static const filesPerPage = 25;
  static const defaultConfidence = 0.8;

  OrganizeState(List<MediaGroup> groups, {this.typeHint, this.readFile})
    : groups = [for (final group in groups) GroupState(group)];

  /// Groups that need a decision. One without videos has nothing to anchor
  /// a path to; its files go to review unless the model decides it anyway.
  List<GroupState> get required => [
    for (final g in groups)
      if (g.group.videos.isNotEmpty) g,
  ];

  List<GroupState> get undecided => [
    for (final g in required)
      if (!g.resolved) g,
  ];

  GroupState find(Object? value) {
    final raw = switch (value) {
      num v => '${v.toInt()}',
      _ => value?.toString().trim().toLowerCase() ?? '',
    };
    final id = RegExp(r'^\d+$').hasMatch(raw) ? 'g$raw' : raw;
    for (final g in groups) {
      if (g.group.id == id) return g;
    }
    throw ToolError(
      raw.isEmpty
          ? 'group is required: an id from list_groups, e.g. "g1".'
          : 'There is no group "$raw". Call list_groups to see the group ids.',
    );
  }

  String nextId() {
    final used = groups
        .map((g) => int.tryParse(g.group.id.substring(1)) ?? 0)
        .fold(0, math.max);
    return 'g${used + 1}';
  }

  String groupsPage(int page) => _paged(
    [for (final g in groups) _summary(g)],
    page: page,
    perPage: groupsPerPage,
    what: 'Groups',
    more: 'list_groups',
  );

  String filesPage(GroupState g, int page) {
    final files = g.group.files;
    final planned = Map<ParsedFile, PlannedTarget>.identity()
      ..addEntries([for (final t in g.planned) MapEntry(t.file, t)]);
    return _paged(
      [
        for (var i = 0; i < files.length; i++)
          _fileLine(g.group, files, i, planned[files[i]]),
      ],
      page: page,
      perPage: filesPerPage,
      what: 'Files of ${g.group.id}',
      more: 'list_group_files for ${g.group.id} with',
    );
  }

  /// What a decision produced, as the model's cue to correct it.
  String placementReport(GroupState g) {
    final decision = g.decision!;
    final placed = [
      for (final t in g.planned)
        if (t.target != null) t,
    ];
    final missed = [
      for (final t in g.planned)
        if (t.target == null) t,
    ];
    final clashes = <String>[];
    for (final t in placed) {
      final target = t.target!.toLowerCase();
      for (final other in groups) {
        if (identical(other, g) || other.decision == null) continue;
        if (other.planned.any((o) => o.target?.toLowerCase() == target)) {
          clashes.add('"${t.target}" is also planned for ${other.group.id}');
          break;
        }
      }
      if (clashes.length >= 3) break;
    }
    final samples = placed.length <= 4
        ? placed
        : [...placed.take(3), placed.last];
    final left = undecided.length;
    return [
      'Decided ${g.group.id} as ${_typeName(decision.type)} '
          '"${decision.title}" → ${JellyfinNaming.titleFolder(decision)}.',
      'Placed ${placed.length} of ${g.planned.length} file(s)'
          '${samples.isEmpty ? '.' : ', e.g.:'}',
      for (final t in samples) '  ${_name(t.file)} => ${t.target}',
      if (missed.isNotEmpty) ...[
        'Not placed (left for the user to review):',
        for (final t in missed.take(8)) '  ${_name(t.file)}: ${t.problem}',
        if (missed.length > 8) '  … and ${missed.length - 8} more',
      ],
      if (clashes.isNotEmpty) ...[
        'Conflicts with other groups:',
        for (final clash in clashes) '  $clash',
      ],
      if (missed.isNotEmpty || clashes.isNotEmpty)
        'If a wrong season, offset or title caused this, submit the group '
            'again; if some files belong to another title, use split_group.',
      left == 0 ? 'Every group is decided.' : '$left group(s) still undecided.',
    ].join('\n');
  }

  OrganizePlan buildPlan({
    required int promptTokens,
    required int completionTokens,
  }) {
    final rows =
        <({ParsedFile file, String? target, double confidence, String note})>[];
    for (final g in groups) {
      if (g.decision != null) {
        for (final t in g.planned) {
          rows.add((
            file: t.file,
            target: t.target,
            confidence: g.confidence,
            note: t.target == null ? 'Not placed: ${t.problem}' : g.note,
          ));
        }
        continue;
      }
      final note = g.unsureReason != null
          ? 'Unsure: ${g.unsureReason}'
          : g.group.videos.isEmpty
          ? 'No video in this group to place these files by'
          : 'The model did not decide this group';
      for (final file in g.group.files) {
        rows.add((file: file, target: null, confidence: 0, note: note));
      }
    }

    final uses = <String, int>{};
    for (final row in rows) {
      if (row.target case final target?) {
        uses.update(target.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final actions = <OrganizeAction>[];
    for (final row in rows) {
      final source = p.posix.joinAll(p.split(row.file.relativePath));
      final target = row.target;
      // Already where Jellyfin wants it: nothing to move.
      if (target != null && target == source) continue;
      // Two files planned onto one path: applying both would lose one.
      final clash = target != null && uses[target.toLowerCase()]! > 1;
      actions.add(
        OrganizeAction(
          source: row.file.relativePath,
          target: target ?? source,
          kind: row.file.extraType != null
              ? 'extra'
              : (row.file.kind.isEmpty ? 'other' : row.file.kind.toLowerCase()),
          confidence: target == null || clash ? 0 : row.confidence,
          note: clash ? 'Another file is planned for the same path' : row.note,
        ),
      );
    }

    final types = {for (final g in groups) ?g.decision?.type};
    final firstDecision = groups
        .map((g) => g.decision)
        .whereType<GroupDecision>()
        .firstOrNull;
    return OrganizePlan(
      mediaType: switch (types.length) {
        0 => 'unknown',
        1 => _typeName(types.single),
        _ => 'mixed',
      },
      targetRoot: firstDecision == null
          ? ''
          : JellyfinNaming.titleFolder(firstDecision).split('/').first,
      reasoning: [
        for (final g in groups.take(40))
          if (g.decision case final d?)
            '${g.group.id} ${_folderLabel(g.group.folder)} → '
                '${JellyfinNaming.titleFolder(d)}'
                '${g.note.isEmpty ? '' : ': ${g.note}'}'
          else if (g.unsureReason case final reason?)
            '${g.group.id} ${_folderLabel(g.group.folder)}: unsure — $reason',
      ],
      actions: actions,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  String _summary(GroupState g) {
    final group = g.group;
    final years = {for (final v in group.videos) ?v.year}.toList()..sort();
    final episodes = _episodes(group.videos);
    return [
      '${group.id}: folder ${_folderLabel(group.folder)}',
      '${group.videos.length} video(s), ${group.companions.length} other '
          'file(s)',
      ?episodes,
      if (years.isNotEmpty) 'year ${years.join('/')}',
      if (group.titleGuess.isNotEmpty) 'title guess "${group.titleGuess}"',
      if (_samples(group) case final samples when samples.isNotEmpty)
        'e.g. ${samples.join(', ')}',
      switch (g) {
        GroupState(:final decision?) =>
          'decided: ${JellyfinNaming.titleFolder(decision)}',
        GroupState(:final unsureReason?) => 'unsure: $unsureReason',
        _ when group.videos.isEmpty => 'no videos (optional)',
        _ => 'UNDECIDED',
      },
    ].join(' · ');
  }

  static String _fileLine(
    MediaGroup group,
    List<ParsedFile> files,
    int index,
    PlannedTarget? planned,
  ) {
    final file = files[index];
    final line = StringBuffer(
      '${index + 1}. ${file.relativePath} [${describeFile(file)}]',
    );
    if (!group.videos.contains(file)) {
      final owner = group.videoFor(file);
      final at = owner == null ? -1 : files.indexOf(owner);
      if (at >= 0) line.write(' (goes with ${at + 1})');
    }
    if (planned != null) {
      line.write(
        planned.target != null
            ? ' => ${planned.target}'
            : ' => not placed: ${planned.problem}',
      );
    }
    return line.toString();
  }

  static String describeFile(ParsedFile file) {
    String two(int n) => n.toString().padLeft(2, '0');
    return [
      if (file.kind.isEmpty) 'other' else file.kind.toLowerCase(),
      if (file.episode case final episode?)
        '${file.season == null ? '' : 'S${two(file.season!)}'}'
            'E${two(episode)}'
            '${file.episodeEnd == null ? '' : '-E${two(file.episodeEnd!)}'}'
      else if (file.season case final season?)
        'season $season',
      if (file.year case final year?) 'year $year',
      if (file.part case final part?) 'part $part',
      if (file.special) 'special',
      if (file.extraType case final extra?) 'extra: $extra',
      if (file.language case final language?) 'language $language',
    ].join(', ');
  }

  static String? _episodes(List<ParsedFile> videos) {
    final main = [
      for (final v in videos)
        if (v.episode != null && !v.special && v.extraType == null) v,
    ];
    final specials = videos.where((v) => v.special).length;
    final extras = videos.where((v) => v.extraType != null).length;
    final parts = [
      if (main.isNotEmpty)
        '${_seasons(main)}episodes '
            '${main.map((v) => v.episode!).reduce(math.min)}-'
            '${main.map((v) => v.episodeEnd ?? v.episode!).reduce(math.max)}',
      if (specials > 0) '$specials special(s)',
      if (extras > 0) '$extras extra(s)',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String _seasons(List<ParsedFile> videos) {
    final seasons = {for (final v in videos) ?v.season}.toList()..sort();
    return seasons.isEmpty ? '' : 'season ${seasons.join('/')}, ';
  }

  static List<String> _samples(MediaGroup group) {
    final pool = group.videos.isNotEmpty ? group.videos : group.companions;
    if (pool.isEmpty) return const [];
    final picks = <ParsedFile>{pool.first, pool[pool.length ~/ 2], pool.last};
    return [for (final file in picks) '"${_clip(_name(file), 80)}"'];
  }

  static String _name(ParsedFile file) => '${file.baseName}${file.extension}';

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1)}…';

  static String _folderLabel(String folder) =>
      folder.isEmpty ? '(top level)' : '"$folder"';

  static String _typeName(GroupMediaType type) =>
      type == GroupMediaType.movie ? 'movie' : 'series';

  static String _paged(
    List<String> lines, {
    required int page,
    required int perPage,
    required String what,
    required String more,
  }) {
    if (lines.isEmpty) return '$what: none.';
    final pages = (lines.length + perPage - 1) ~/ perPage;
    if (page > pages) {
      throw ToolError(
        '$what has only $pages page(s); ask for page 1 to $pages.',
      );
    }
    final start = (page - 1) * perPage;
    return [
      '$what — page $page of $pages:',
      ...lines.sublist(start, math.min(lines.length, start + perPage)),
      if (page < pages) '(more: call $more page ${page + 1})',
    ].join('\n');
  }

  static int? integer(Object? value) => switch (value) {
    num v => v.toInt(),
    String v => int.tryParse(v.trim()),
    _ => null,
  };

  static double confidenceOf(Object? value) {
    final n = switch (value) {
      num v => v.toDouble(),
      String v => double.tryParse(v.trim()),
      _ => null,
    };
    if (n == null) return defaultConfidence;
    return (n > 1 ? n / 100 : n).clamp(0.0, 1.0);
  }
}

const _groupParameter = {
  'type': 'string',
  'description': 'A group id from list_groups, e.g. "g1".',
};

const _pageParameter = {
  'type': 'integer',
  'description': 'Page number, starting at 1.',
};

class _ListGroupsTool extends AgentTool<OrganizeState> {
  const _ListGroupsTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'list_groups',
    description:
        'Lists the groups of files a page at a time: sample file names, what '
        'was parsed from them, and whether each group is decided.',
    parameters: {
      'type': 'object',
      'properties': {'page': _pageParameter},
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, OrganizeState context) =>
      context.groupsPage(pageArgument(arguments['page']));
}

class _ListGroupFilesTool extends AgentTool<OrganizeState> {
  const _ListGroupFilesTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'list_group_files',
    description:
        'Lists every file in one group, numbered, with what was parsed from '
        'its name and — once the group is decided — the path it will get.',
    parameters: {
      'type': 'object',
      'properties': {'group': _groupParameter, 'page': _pageParameter},
      'required': ['group'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, OrganizeState context) =>
      context.filesPage(
        context.find(arguments['group']),
        pageArgument(arguments['page']),
      );
}

class _ReadExistingNfoTool extends AgentTool<OrganizeState> {
  const _ReadExistingNfoTool();

  static const _shown = 5;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'read_existing_nfo',
    description:
        'Reads the title and year from NFO files already in a group, which '
        'often name the title more reliably than the file names.',
    parameters: {
      'type': 'object',
      'properties': {'group': _groupParameter},
      'required': ['group'],
    },
  );

  @override
  Future<String> execute(
    Map<String, dynamic> arguments,
    OrganizeState context,
  ) async {
    final g = context.find(arguments['group']);
    final nfos = [
      for (final file in g.group.files)
        if (file.extension == '.nfo') file,
    ];
    final read = context.readFile;
    if (nfos.isEmpty || read == null) {
      return 'Group ${g.group.id} has no NFO files.';
    }
    final lines = <String>[];
    for (final file in nfos.take(_shown)) {
      final xml = await read(file.relativePath);
      final metadata = xml == null ? null : NfoReader.read(xml);
      if (metadata == null) {
        lines.add('${file.relativePath}: not readable');
        continue;
      }
      final root = NfoReader.rootElementName(xml);
      lines.add(
        '${file.relativePath} (<$root>): '
        'title ${metadata.title == null ? 'none' : '"${metadata.title}"'}, '
        'year ${metadata.year ?? 'none'}',
      );
    }
    if (nfos.length > _shown) {
      lines.add('… and ${nfos.length - _shown} more NFO file(s)');
    }
    return lines.join('\n');
  }
}

class _SubmitGroupTool extends AgentTool<OrganizeState> {
  const _SubmitGroupTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'submit_group',
    description:
        'Decides what one group is. The app builds every path from this; the '
        'reply shows them and any file that could not be placed. Submitting '
        'a group again replaces the earlier decision.',
    parameters: {
      'type': 'object',
      'properties': {
        'group': _groupParameter,
        'mediaType': {
          'type': 'string',
          'enum': ['movie', 'series'],
        },
        'title': {
          'type': 'string',
          'description':
              'The real title, in the language the names use, without '
              'release tags.',
        },
        'year': {
          'type': 'integer',
          'description': 'Only when a name, the folder or an NFO states it.',
        },
        'season': {
          'type': 'integer',
          'description':
              'Season for files whose names carry none. Omit for season 1.',
        },
        'episodeOffset': {
          'type': 'integer',
          'description':
              'Added to every parsed episode number, e.g. -12 when season 2 '
              'continues from episode 13. Usually omitted.',
        },
        'confidence': {
          'type': 'number',
          'description': '0 to 1. Below 0.6 the files are flagged for review.',
        },
        'note': {'type': 'string', 'description': 'One short sentence: why.'},
      },
      'required': ['group', 'mediaType', 'title'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, OrganizeState context) {
    final g = context.find(arguments['group']);
    final type = switch (arguments['mediaType']
        ?.toString()
        .trim()
        .toLowerCase()) {
      'movie' || 'film' => GroupMediaType.movie,
      'series' || 'show' || 'tv' => GroupMediaType.series,
      _ => null,
    };
    if (type == null) {
      throw const ToolError(
        'mediaType must be "movie" or "series". If you cannot tell, call '
        'mark_unsure.',
      );
    }
    final hint = context.typeHint;
    if (hint != null && hint != GroupMediaType.unknown && type != hint) {
      final wanted = hint == GroupMediaType.movie ? 'movie' : 'series';
      throw ToolError(
        'The user said this folder holds ${wanted}s. Submit mediaType '
        '"$wanted", or call mark_unsure if this group is something else.',
      );
    }
    final title = arguments['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      throw const ToolError(
        'title is required: the real title, without release tags.',
      );
    }
    var year = OrganizeState.integer(arguments['year']);
    if (year == 0) year = null;
    if (year != null && (year < 1900 || year > 2100)) {
      throw const ToolError(
        'year must be a four-digit year. Omit it when no name states one.',
      );
    }
    final season = OrganizeState.integer(arguments['season']);
    if (season != null && season < 0) {
      throw const ToolError('season cannot be negative. Use 0 for specials.');
    }

    g.decide(
      GroupDecision(
        type: type,
        title: title,
        year: year,
        season: season,
        episodeOffset: OrganizeState.integer(arguments['episodeOffset']) ?? 0,
      ),
      OrganizeState.confidenceOf(arguments['confidence']),
      arguments['note']?.toString().trim() ?? '',
    );
    return context.placementReport(g);
  }
}

class _SplitGroupTool extends AgentTool<OrganizeState> {
  const _SplitGroupTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'split_group',
    description:
        'Moves files that do not belong to a group into a new group. Both '
        'groups are undecided afterwards.',
    parameters: {
      'type': 'object',
      'properties': {
        'group': _groupParameter,
        'files': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description':
              'Numbers from list_group_files of the files to move out.',
        },
        'reason': {'type': 'string'},
      },
      'required': ['group', 'files'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, OrganizeState context) {
    final g = context.find(arguments['group']);
    final all = g.group.files;
    final numbers = arguments['files'];
    if (numbers is! List || numbers.isEmpty) {
      throw const ToolError(
        'files must be a list of file numbers from list_group_files.',
      );
    }
    final picked = <ParsedFile>{};
    for (final value in numbers) {
      final n = OrganizeState.integer(value);
      if (n == null || n < 1 || n > all.length) {
        throw ToolError(
          '$value is not a file of ${g.group.id}; its files are numbered 1 '
          'to ${all.length}. Call list_group_files to see them.',
        );
      }
      picked.add(all[n - 1]);
    }
    if (picked.length == all.length) {
      throw const ToolError(
        'That is every file in the group. Decide the group instead.',
      );
    }

    MediaGroup part(String id, bool Function(ParsedFile) keep) {
      final companions = [
        for (final f in g.group.companions)
          if (keep(f)) f,
      ];
      return MediaGroup(
        id: id,
        folder: g.group.folder,
        seriesKey: g.group.seriesKey,
        videos: [
          for (final f in g.group.videos)
            if (keep(f)) f,
        ],
        companions: companions,
        // A subtitle whose episode moved to the other group is no longer
        // anyone's in particular; it becomes a folder-level file here.
        companionVideos: {
          for (final c in companions)
            if (g.group.videoFor(c) case final video? when keep(video))
              c.relativePath: video,
        },
      );
    }

    final id = context.nextId();
    final moved = GroupState(part(id, picked.contains));
    g.reset(part(g.group.id, (f) => !picked.contains(f)));
    context.groups.insert(context.groups.indexOf(g) + 1, moved);
    return 'Moved ${picked.length} file(s) from ${g.group.id} into $id. Both '
        'are undecided now; list_group_files shows what each holds.';
  }
}

class _MarkUnsureTool extends AgentTool<OrganizeState> {
  const _MarkUnsureTool();

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'mark_unsure',
    description:
        'Leaves a group for the user to review, when you cannot tell what it '
        'is.',
    parameters: {
      'type': 'object',
      'properties': {
        'group': _groupParameter,
        'reason': {'type': 'string', 'description': 'One short sentence.'},
      },
      'required': ['group'],
    },
  );

  @override
  String execute(Map<String, dynamic> arguments, OrganizeState context) {
    final g = context.find(arguments['group']);
    final reason = arguments['reason']?.toString().trim() ?? '';
    g.markUnsure(reason.isEmpty ? 'the model could not tell' : reason);
    final left = context.undecided.length;
    return 'Marked ${g.group.id} unsure; its files are left for the user. '
        '${left == 0 ? 'Every group is decided.' : '$left group(s) still undecided.'}';
  }
}
