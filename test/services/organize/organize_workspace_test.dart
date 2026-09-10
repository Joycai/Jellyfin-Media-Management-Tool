import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/organize/jellyfin_naming.dart';
import 'package:jellyfin_media_management_tool/services/organize/organize_workspace.dart';

import '../../helpers/fs.dart';

const _root = '/support/agent';
const _base = '/work/Some Show';

FileStamp _stamp(String path, {int size = 100}) => FileStamp(
  relativePath: path,
  size: size,
  modified: DateTime.utc(2026, 9, 1, 12),
);

const _decided = CachedDecision(
  decision: GroupDecision(
    type: GroupMediaType.series,
    title: 'Some Show',
    year: 2020,
    season: 2,
  ),
  confidence: 0.9,
  note: 'from the names',
);

void main() {
  late FileSystem fs;
  late OrganizeWorkspace workspace;

  setUp(() {
    fs = newMemoryFs();
    workspace = OrganizeWorkspace(fs: fs, root: _root);
  });

  group('decisions', () {
    test('come back for the same folder, after a restart', () async {
      await workspace.saveDecision(_base, 'g-key', _decided);

      final reopened = OrganizeWorkspace(fs: fs, root: _root);
      final loaded = (await reopened.loadDecisions(_base))['g-key']!;

      expect(loaded.decision.type, GroupMediaType.series);
      expect(loaded.decision.title, 'Some Show');
      expect(loaded.decision.year, 2020);
      expect(loaded.decision.season, 2);
      expect(loaded.confidence, 0.9);
      expect(loaded.note, 'from the names');
      expect(await reopened.loadDecisions('/work/Other'), isEmpty);
    });

    test('a group key follows its files, not their order', () {
      final a = _stamp('01.mkv');
      final b = _stamp('02.mkv');

      expect(
        workspace.groupKey(_base, [a, b]),
        workspace.groupKey(_base, [b, a]),
      );
      // A re-encoded episode is a different file; its old decision is not
      // evidence about the new one.
      expect(
        workspace.groupKey(_base, [a, b]),
        isNot(workspace.groupKey(_base, [a, _stamp('02.mkv', size: 101)])),
      );
    });

    test('a corrupt file reads as nothing remembered', () async {
      await workspace.saveDecision(_base, 'g-key', _decided);
      final file = fs
          .directory('$_root/organize')
          .listSync()
          .whereType<File>()
          .single;
      file.writeAsStringSync('{not json');

      expect(await workspace.loadDecisions(_base), isEmpty);
      // And it does not stop the next write.
      await workspace.saveDecision(_base, 'g-key', _decided);
      expect(await workspace.loadDecisions(_base), hasLength(1));
    });

    test('prune drops old folders and keeps only the newest', () async {
      final dir = fs.directory('$_root/organize')..createSync(recursive: true);
      final now = DateTime.now();
      for (var i = 0; i < OrganizeWorkspace.maxFolders + 1; i++) {
        dir
            .childFile('recent$i.json')
            .writeAsStringSync(
              jsonEncode({
                'updatedAt': now.subtract(Duration(hours: i)).toIso8601String(),
              }),
            );
      }
      dir
          .childFile('old.json')
          .writeAsStringSync(
            jsonEncode({
              'updatedAt': now
                  .subtract(const Duration(days: 8))
                  .toIso8601String(),
            }),
          );

      await workspace.prune();

      final left = dir.listSync().map((e) => fs.path.basename(e.path)).toSet();
      expect(left, hasLength(OrganizeWorkspace.maxFolders));
      expect(left, isNot(contains('old.json')));
      expect(
        left,
        isNot(contains('recent${OrganizeWorkspace.maxFolders}.json')),
      );
    });
  });

  group('corrections', () {
    const target = 'Shows/Right (2011)/Season 01/Right S01E01.mkv';

    test('are found where the file was and where it went', () async {
      await workspace.recordEdits(_base, [
        CorrectedFile(stamp: _stamp('ep1.mkv'), target: target, isVideo: true),
      ]);

      expect(await workspace.overridesFor(_base, [_stamp('ep1.mkv')]), {
        'ep1.mkv': target,
      });
      // After the move the file sits at the target, same size and mtime.
      expect(await workspace.overridesFor(_base, [_stamp(target)]), {
        target: target,
      });
      // A changed file is not the file the user corrected.
      expect(
        await workspace.overridesFor(_base, [_stamp('ep1.mkv', size: 7)]),
        isEmpty,
      );
    });

    test('age out when unused', () async {
      final stale = DateTime.now().subtract(const Duration(days: 200));
      fs.file('$_root/overrides.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'entries': {
              'old-key': {'target': 'x', 'lastUsed': stale.toIso8601String()},
            },
          }),
        );

      await workspace.recordEdits(_base, [
        CorrectedFile(stamp: _stamp('ep1.mkv'), target: target, isVideo: true),
      ]);

      final json =
          jsonDecode(fs.file('$_root/overrides.json').readAsStringSync())
              as Map<String, dynamic>;
      final entries = json['entries'] as Map<String, dynamic>;
      expect(entries.keys, isNot(contains('old-key')));
      expect(entries, hasLength(2));
    });

    test('agreeing on a new title folder revise the group decision', () async {
      await workspace.saveDecision(_base, 'g-key', _decided);

      await workspace.recordEdits(_base, [
        for (final n in [1, 2])
          CorrectedFile(
            stamp: _stamp('ep$n.mkv'),
            target:
                'Shows/Right Title (2011)/Season 02/Right Title S02E0$n.mkv',
            isVideo: true,
            groupKey: 'g-key',
          ),
      ]);

      final revised = (await workspace.loadDecisions(_base))['g-key']!;
      expect(revised.decision.title, 'Right Title');
      expect(revised.decision.year, 2011);
      expect(revised.decision.type, GroupMediaType.series);
      // What the user did not touch is kept.
      expect(revised.decision.season, 2);
      expect(revised.confidence, 1);
    });

    test('disagreeing ones leave the decision alone', () async {
      await workspace.saveDecision(_base, 'g-key', _decided);

      await workspace.recordEdits(_base, [
        CorrectedFile(
          stamp: _stamp('ep1.mkv'),
          target: 'Shows/One/Season 01/One S01E01.mkv',
          isVideo: true,
          groupKey: 'g-key',
        ),
        CorrectedFile(
          stamp: _stamp('ep2.mkv'),
          target: 'Shows/Two/Season 01/Two S01E02.mkv',
          isVideo: true,
          groupKey: 'g-key',
        ),
      ]);

      expect(
        (await workspace.loadDecisions(_base))['g-key']!.decision.title,
        'Some Show',
      );
    });
  });

  group('CachedDecision.revisedBy', () {
    test('follows the library root to the type', () {
      final revised = _decided.revisedBy([
        'Movies/Some Film (1999)/Some Film (1999).mkv',
      ])!;

      expect(revised.decision.type, GroupMediaType.movie);
      expect(revised.decision.title, 'Some Film');
      expect(revised.decision.year, 1999);
    });

    test('says nothing when the folder is the decided one', () {
      expect(
        _decided.revisedBy([
          'Shows/Some Show (2020)/Season 02/Some Show S02E09.mkv',
        ]),
        isNull,
      );
    });

    test('ignores a target with no title folder', () {
      expect(_decided.revisedBy(['loose.mkv']), isNull);
    });
  });
}
