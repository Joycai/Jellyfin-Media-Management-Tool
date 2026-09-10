import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/organize/filename_parser.dart';
import 'package:jellyfin_media_management_tool/services/organize/jellyfin_naming.dart';
import 'package:jellyfin_media_management_tool/services/organize/organize_agent.dart';
import 'package:path/path.dart' as p;

import '../../helpers/ai.dart';

List<ParsedFile> _files(List<List<String>> paths) => [
  for (final segments in paths) FilenameParser.parse(p.joinAll(segments)),
];

final _show = _files([
  ['Some Show', 'Some Show - 01.mkv'],
  ['Some Show', 'Some Show - 02.mkv'],
  ['Some Show', 'Some Show - 01.chs.ass'],
]);

ChatTurn _submit(Map<String, Object?> decision) =>
    (_) => toolTurn([('submit_group', decision)]);

String _lastResult(ScriptedChatProvider provider, int call) =>
    (provider.seen[call].last as ToolResultMessage).content;

void main() {
  test('one decision places a whole series, subtitles included', () async {
    final provider = ScriptedChatProvider([
      _submit({
        'group': 'g1',
        'mediaType': 'series',
        'title': 'Some Show',
        'year': 2020,
        'confidence': 0.9,
      }),
    ]);

    final run = await OrganizeAgent(
      provider,
    ).run(folderName: 'Some Show', files: _show);

    // The run ends on the round that decided the last group — a small model
    // should not spend a turn announcing it is finished.
    expect(provider.calls, 1);
    expect(run.rounds, 1);
    final targets = run.plan.actions.map((a) => a.target).toList();
    expect(
      targets,
      contains('Shows/Some Show (2020)/Season 01/Some Show S01E01.mkv'),
    );
    expect(
      targets,
      contains('Shows/Some Show (2020)/Season 01/Some Show S01E02.mkv'),
    );
    expect(
      targets.where((t) => t.endsWith('.ass')).single,
      startsWith('Shows/Some Show (2020)/Season 01/Some Show S01E01'),
    );
    expect(
      run.plan.actions.every((a) => a.status == ActionStatus.pending),
      isTrue,
    );
    expect(run.plan.mediaType, 'series');
    expect(run.plan.targetRoot, 'Shows');
    expect(run.plan.promptTokens, 10);
  });

  test('the model starts from the groups and is offered group tools', () async {
    final provider = ScriptedChatProvider([
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Some Show'}),
    ]);

    await OrganizeAgent(
      provider,
    ).run(folderName: 'Some Show', files: _show, titleHint: 'Some Show');

    final task = (provider.seen.first[1] as UserMessage).content;
    expect(task, contains('g1'));
    expect(task, contains('UNDECIDED'));
    expect(task, contains('The user gives the title "Some Show"'));
    expect(provider.offeredTools.first, [
      'list_groups',
      'list_group_files',
      'read_existing_nfo',
      'submit_group',
      'split_group',
      'mark_unsure',
    ]);
  });

  test('a bad submission is refused with the next step, then fixed', () async {
    final provider = ScriptedChatProvider([
      _submit({'group': 'g1', 'mediaType': 'documentary', 'title': 'X'}),
      _submit({'group': 'g9', 'mediaType': 'series', 'title': 'X'}),
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Some Show'}),
    ]);

    final run = await OrganizeAgent(
      provider,
    ).run(folderName: 'Some Show', files: _show);

    expect(_lastResult(provider, 1), contains('mediaType must be'));
    expect(_lastResult(provider, 2), contains('Call list_groups'));
    expect(run.rounds, 3);
    expect(run.plan.actions, isNotEmpty);
  });

  test('the submission reply shows the paths it produced', () async {
    final provider = ScriptedChatProvider([
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Some Show'}),
      (_) => textTurn('Done.'),
    ]);
    final files = _files([
      ['Some Show', 'Some Show - 01.mkv'],
      ['Some Show', 'Some Show - OVA.mkv'],
      ['Other', 'Other Film (2001).mkv'],
    ]);

    await OrganizeAgent(provider).run(folderName: 'Mixed', files: files);

    final report = _lastResult(provider, 1);
    expect(report, contains('Shows/Some Show'));
    expect(report, contains('group(s) still undecided'));
  });

  test('an undecided group still reaches the preview, flagged', () async {
    final files = _files([
      ['A', 'Show A - 01.mkv'],
      ['A', 'Show A - 02.mkv'],
      ['B', 'Movie B (2019).mkv'],
    ]);
    final provider = ScriptedChatProvider([
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Show A'}),
      (_) => textTurn('That is all.'),
    ]);

    final run = await OrganizeAgent(
      provider,
    ).run(folderName: 'Media', files: files);

    // One decision, then a reply and two reminders that went unanswered.
    expect(provider.calls, 4);
    final movie = run.plan.actions.singleWhere(
      (a) => a.source.contains('Movie B'),
    );
    expect(movie.status, ActionStatus.needsReview);
    expect(movie.note, contains('did not decide'));
    expect(
      (provider.seen[2].last as UserMessage).content,
      contains('Still undecided: g2'),
    );
  });

  test('mark_unsure leaves the group for the user', () async {
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        ('mark_unsure', {'group': 'g1', 'reason': 'no idea what this is'}),
      ]),
    ]);

    final run = await OrganizeAgent(
      provider,
    ).run(folderName: 'Some Show', files: _show);

    expect(run.plan.actions, hasLength(3));
    for (final action in run.plan.actions) {
      expect(action.status, ActionStatus.needsReview);
      expect(action.note, 'Unsure: no idea what this is');
      // Nothing moves: an unsure row keeps its own path.
      expect(action.target, p.posix.joinAll(p.split(action.source)));
    }
  });

  test('split_group moves files into a new group to decide', () async {
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        (
          'split_group',
          {
            'group': 'g1',
            'files': [2],
            'reason': 'another show',
          },
        ),
      ]),
      (_) => toolTurn([
        (
          'submit_group',
          {'group': 'g1', 'mediaType': 'series', 'title': 'Some Show'},
        ),
        (
          'submit_group',
          {'group': 'g2', 'mediaType': 'series', 'title': 'Other Show'},
        ),
      ]),
    ]);

    final run = await OrganizeAgent(
      provider,
    ).run(folderName: 'Some Show', files: _show);

    expect(_lastResult(provider, 1), contains('into g2'));
    final targets = run.plan.actions.map((a) => a.target);
    expect(
      targets,
      contains('Shows/Other Show/Season 01/Other Show S01E02.mkv'),
    );
    expect(targets, contains('Shows/Some Show/Season 01/Some Show S01E01.mkv'));
  });

  test('two groups planned onto one path are both flagged', () async {
    final files = _files([
      ['A', 'Show - 01.mkv'],
      ['B', 'Show - 01.mkv'],
    ]);
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        (
          'submit_group',
          {'group': 'g1', 'mediaType': 'series', 'title': 'Show'},
        ),
        (
          'submit_group',
          {'group': 'g2', 'mediaType': 'series', 'title': 'Show'},
        ),
      ]),
    ]);

    final run = await OrganizeAgent(
      provider,
    ).run(folderName: 'Media', files: files);

    // Applying both would lose one file to the other.
    expect(run.plan.actions, hasLength(2));
    for (final action in run.plan.actions) {
      expect(action.status, ActionStatus.needsReview);
      expect(action.note, contains('same path'));
    }
  });

  test('the user\'s media type is enforced', () async {
    final provider = ScriptedChatProvider([
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Some Show'}),
      _submit({'group': 'g1', 'mediaType': 'movie', 'title': 'Some Show'}),
    ]);

    await OrganizeAgent(provider).run(
      folderName: 'Some Show',
      files: _show,
      typeHint: GroupMediaType.movie,
    );

    expect(_lastResult(provider, 1), contains('The user said'));
  });

  test('read_existing_nfo reports what an NFO names', () async {
    final files = _files([
      ['Show', 'Show - 01.mkv'],
      ['Show', 'tvshow.nfo'],
    ]);
    final provider = ScriptedChatProvider([
      (_) => toolTurn([
        ('read_existing_nfo', {'group': 'g1'}),
      ]),
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Real Title'}),
    ]);

    await OrganizeAgent(provider).run(
      folderName: 'Show',
      files: files,
      readFile: (path) async => path.endsWith('.nfo')
          ? '<tvshow><title>Real Title</title>'
                '<premiered>2011-04-17</premiered></tvshow>'
          : null,
    );

    final report = _lastResult(provider, 1);
    expect(report, contains('"Real Title"'));
    expect(report, contains('2011'));
  });

  test('a model that decides nothing fails loudly', () async {
    final provider = ScriptedChatProvider([
      (_) => textTurn('I cannot help with that.'),
    ]);

    await expectLater(
      OrganizeAgent(provider).run(folderName: 'Some Show', files: _show),
      throwsA(isA<AiException>()),
    );
  });

  test('a folder with no videos needs no model at all', () async {
    final provider = ScriptedChatProvider([(_) => textTurn('unused')]);
    var checked = false;

    final run =
        await OrganizeAgent(
          provider,
          beforeStart: () async => checked = true,
        ).run(
          folderName: 'Art',
          files: _files([
            ['poster.jpg'],
          ]),
        );

    expect(provider.calls, 0);
    expect(checked, isFalse);
    expect(run.rounds, 0);
    expect(run.plan.actions.single.status, ActionStatus.needsReview);
  });

  test('runs the readiness check before the first model call', () async {
    final provider = ScriptedChatProvider([(_) => textTurn('unused')]);

    await expectLater(
      OrganizeAgent(
        provider,
        beforeStart: () async => throw const AiException('no tools'),
      ).run(folderName: 'Some Show', files: _show),
      throwsA(isA<AiException>()),
    );
    expect(provider.calls, 0);
  });

  test('reports progress as groups are decided', () async {
    final files = _files([
      ['A', 'Show A - 01.mkv'],
      ['B', 'Movie B (2019).mkv'],
    ]);
    final provider = ScriptedChatProvider([
      _submit({'group': 'g1', 'mediaType': 'series', 'title': 'Show A'}),
      _submit({'group': 'g2', 'mediaType': 'movie', 'title': 'Movie B'}),
    ]);
    final progress = <(int, int)>[];

    await OrganizeAgent(provider).run(
      folderName: 'Media',
      files: files,
      onProgress: (resolved, total) => progress.add((resolved, total)),
    );

    expect(progress, [(0, 2), (1, 2), (2, 2)]);
  });
}
