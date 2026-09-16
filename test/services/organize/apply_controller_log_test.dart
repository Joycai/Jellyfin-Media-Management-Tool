import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/organize/apply_controller.dart';
import 'package:path/path.dart' as p;

/// Five real files under a temp base dir, so [ApplyController.start] has
/// something to move and the log fills with `moved` entries rather than
/// failures. `applyOrganizeAction` resolves against the real filesystem, which
/// is why this is a temp directory and not the in-memory helper.
const _count = 5;

OrganizeAction _action(int i) => OrganizeAction(
  source: p.join('flat', 'file$i.mkv'),
  target: p.join('Movies', 'File $i', 'File $i.mkv'),
  kind: 'video',
  confidence: 0.9,
  note: '',
);

OrganizePlan _plan() => OrganizePlan(
  mediaType: 'movie',
  targetRoot: 'Movies',
  reasoning: const [],
  actions: [for (var i = 0; i < _count; i++) _action(i)],
);

void main() {
  late Directory base;

  setUp(() {
    base = Directory.systemTemp.createTempSync('apply_controller_log');
    final flat = Directory(p.join(base.path, 'flat'))..createSync();
    for (var i = 0; i < _count; i++) {
      File(p.join(flat.path, 'file$i.mkv')).writeAsStringSync('x');
    }
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test('a job under the cap keeps its whole log', () async {
    final c = ApplyController(
      plan: _plan(),
      baseDir: base.path,
      backup: false,
      totalBytes: _count,
    );

    await c.start();

    // started + one moved per file + finished
    expect(c.logLength, _count + 2);
    expect(c.logStart, 0);
    expect(c.logAt(0).kind, LogKind.started);
    expect(c.logAt(c.logLength - 1).kind, LogKind.finished);
    expect(c.status, ApplyStatus.done);
    expect(c.done, _count);
  });

  test(
    'past the cap the oldest entries go, but indices stay absolute',
    () async {
      final c = ApplyController(
        plan: _plan(),
        baseDir: base.path,
        backup: false,
        totalBytes: _count,
        maxLogEntries: 3,
      );

      await c.start();

      expect(c.logLength, _count + 2);
      expect(c.logStart, _count + 2 - 3);

      // What survived is the tail: the last two moves and the finish line.
      final walked = [
        for (var i = c.logStart; i < c.logLength; i++) c.logAt(i),
      ];
      expect(walked.map((e) => e.kind), [
        LogKind.moved,
        LogKind.moved,
        LogKind.finished,
      ]);
      expect(walked[0].name, 'file${_count - 2}.mkv');
      expect(walked[1].name, 'file${_count - 1}.mkv');

      // The dropped range is unreachable rather than silently aliased onto the
      // survivors -- a consumer that walks from a stale cursor must notice.
      expect(() => c.logAt(c.logStart - 1), throwsA(isA<RangeError>()));
    },
  );

  test('the aggregate counts survive the trim', () async {
    final c = ApplyController(
      plan: _plan(),
      baseDir: base.path,
      backup: false,
      totalBytes: _count,
      maxLogEntries: 1,
    );

    await c.start();

    expect(c.logLength, _count + 2);
    expect(c.logStart, _count + 1);
    expect(c.logAt(c.logLength - 1).kind, LogKind.finished);
    expect(c.done, _count);
    expect(c.failed, 0);
    expect(c.result.succeeded, _count);
  });
}
