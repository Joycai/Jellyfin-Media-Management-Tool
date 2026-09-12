import 'dart:collection';
import 'dart:io';

import 'package:file/file.dart' show FileSystem;
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/history_entry.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/apply_controller.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/fs.dart';

const _count = 5;

OrganizeAction _action(int i) => OrganizeAction(
  source: p.join('flat', 'file$i.mkv'),
  target: p.join('Movies', 'File $i', 'File $i.mkv'),
  kind: 'video',
  confidence: 0.9,
  note: '',
);

List<OrganizeAction> _actions([int n = _count]) => [
  for (var i = 0; i < n; i++) _action(i),
];

/// Hands out the first [ok] actions and then throws, the way a platform
/// exception or an OOM in the middle of a batch would. `for (final a in ...)`
/// iterates a ListBase through `length` and `[]`, so the throw lands inside the
/// apply loop with [ok] files already moved.
class _ExplodingActions extends ListBase<OrganizeAction> {
  _ExplodingActions(this.inner, this.ok);

  final List<OrganizeAction> inner;
  final int ok;

  @override
  int get length => inner.length;

  @override
  set length(int value) => inner.length = value;

  @override
  OrganizeAction operator [](int index) {
    if (index >= ok) throw StateError('the batch died at action $index');
    return inner[index];
  }

  @override
  void operator []=(int index, OrganizeAction value) => inner[index] = value;
}

/// A history whose manifest write always fails: a full disk, a read-only undo
/// folder, a permissions change under the app support directory.
class _BrokenHistory extends HistoryService {
  _BrokenHistory() : super(fs: _fs(), undoDir: '/undo');

  static FileSystem _fs() {
    final fs = newMemoryFs();
    fs.directory('/undo').createSync(recursive: true);
    return fs;
  }

  @override
  Future<HistoryEntry> record({
    required HistoryKind kind,
    required String baseDir,
    required int itemCount,
    required int moveCount,
    required int renameCount,
    required int totalBytes,
    required List<Map<String, String>> moves,
  }) async => throw const FileSystemException('undo folder is read-only');
}

void main() {
  late Directory base;
  late FileSystem histFs;
  late HistoryService history;

  setUp(() {
    // The apply loop moves real files -- applyOrganizeAction resolves against
    // the local filesystem -- so the source tree is a temp directory. The undo
    // manifest is written through the injected in-memory one.
    base = Directory.systemTemp.createTempSync('apply_controller_undo');
    final flat = Directory(p.join(base.path, 'flat'))..createSync();
    for (var i = 0; i < _count; i++) {
      File(p.join(flat.path, 'file$i.mkv')).writeAsStringSync('x');
    }
    histFs = newMemoryFs();
    histFs.directory('/undo').createSync(recursive: true);
    history = HistoryService(fs: histFs, undoDir: '/undo');
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  ApplyController makeController({
    List<OrganizeAction>? actions,
    HistoryService? history,
  }) => ApplyController(
    plan: OrganizePlan(
      mediaType: 'movie',
      targetRoot: 'Movies',
      reasoning: const [],
      actions: actions ?? _actions(),
    ),
    baseDir: base.path,
    backup: true,
    totalBytes: _count,
    history: history,
  );

  test('a throw part-way through still writes the undo manifest', () async {
    final c = makeController(
      actions: _ExplodingActions(_actions(), 2),
      history: history,
    );

    await expectLater(c.start(), throwsA(isA<StateError>()));

    // The two files that did move stay recoverable. The manifest write used to
    // sit after the loop, so anything thrown inside it lost the undo for work
    // that had already happened on disk.
    expect(c.done, 2);
    expect(history.entries, hasLength(1));
    expect(history.entries.single.itemCount, 2);

    // And the controller reached a terminal state instead of leaving the
    // progress screen spinning on a job that can no longer advance.
    expect(c.status, ApplyStatus.done);
  });

  test('a manifest write that fails is reported, not thrown', () async {
    final c = makeController(actions: _actions(2), history: _BrokenHistory());

    await c.start();

    expect(c.status, ApplyStatus.done);
    expect(c.done, 2);
    expect(c.undoError, isNotNull);

    final lost = c.log.where((e) => e.kind == LogKind.undoLost).toList();
    expect(lost, hasLength(1));
    expect(lost.single.level, LogLevel.warn);
  });

  test('a batch with nothing to undo writes no manifest', () async {
    final c = makeController(actions: _actions(0), history: history);

    await c.start();

    expect(c.done, 0);
    expect(history.entries, isEmpty);
    expect(c.undoError, isNull);
  });

  test('a successful batch records every move as before', () async {
    final c = makeController(history: history);

    await c.start();

    expect(c.status, ApplyStatus.done);
    expect(c.done, _count);
    expect(c.undoError, isNull);
    expect(history.entries, hasLength(1));
    expect(history.entries.single.itemCount, _count);
  });
}
