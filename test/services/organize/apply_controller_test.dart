import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/organize/apply_controller.dart';
import 'package:path/path.dart' as p;

/// ApplyController drives the only code in the app that moves a user's files,
/// and it was one of two files at 0% coverage. These tests cover the state
/// machine around the loop -- idempotent start, pause, resume, stop, the
/// needs-review skip, and not notifying after dispose -- rather than the move
/// itself, which organize_service_test.dart already covers.
const _count = 12;

OrganizeAction _action(int i, {double confidence = 0.9}) => OrganizeAction(
  source: p.join('flat', 'file$i.mkv'),
  target: p.join('Movies', 'File $i', 'File $i.mkv'),
  kind: 'video',
  confidence: confidence,
  note: '',
);

late Directory base;

/// [base]/flat/fileN.mkv for N in [0, count).
void _seedFiles(int count) {
  final flat = Directory(p.join(base.path, 'flat'))
    ..createSync(recursive: true);
  for (var i = 0; i < count; i++) {
    File(p.join(flat.path, 'file$i.mkv')).writeAsStringSync('x');
  }
}

bool _exists(int i) =>
    File(p.join(base.path, 'Movies', 'File $i', 'File $i.mkv')).existsSync();

ApplyController _controller(List<OrganizeAction> actions) => ApplyController(
  plan: OrganizePlan(
    mediaType: 'movie',
    targetRoot: 'Movies',
    reasoning: const [],
    actions: actions,
  ),
  baseDir: base.path,
  backup: false,
  totalBytes: actions.length,
);

/// Polls until [test] holds, so a test can interleave with a running batch
/// without depending on the controller's artificial pacing.
Future<void> _until(bool Function() test) async {
  for (var i = 0; i < 400 && !test(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(test(), isTrue, reason: 'condition never became true');
}

void main() {
  setUp(() {
    base = Directory.systemTemp.createTempSync('apply_controller_');
    _seedFiles(_count);
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test('a full run applies every action and lands on done', () async {
    final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);

    await c.start();

    expect(c.status, ApplyStatus.done);
    expect(c.done, _count);
    expect(c.failed, 0);
    expect(c.skipped, 0);
    expect(c.fraction, 1.0);
    expect(c.queued, 0);
    expect(c.result.succeeded, _count);
    expect(c.result.failures, isEmpty);
    expect(_exists(0), isTrue);
    expect(_exists(_count - 1), isTrue);
    // started + one line per move + finished
    expect(c.log, hasLength(_count + 2));
  });

  test('start is idempotent', () async {
    final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);

    final first = c.start();
    final second = c.start();
    await first;
    await second;

    // The second call is a no-op rather than a second pass over the plan,
    // which would have found every source already gone and reported failures.
    expect(c.done, _count);
    expect(c.failed, 0);
  });

  test('needsReview actions are skipped, not applied', () async {
    final c = _controller([
      _action(0),
      _action(1, confidence: 0.2), // below the 0.6 floor -> needsReview
      _action(2),
    ]);

    await c.start();

    expect(c.done, 2);
    expect(c.skipped, 1);
    expect(c.failed, 0);
    expect(_exists(0), isTrue);
    expect(_exists(1), isFalse);
    expect(_exists(2), isTrue);
    expect(c.log.where((e) => e.kind == LogKind.skipped), hasLength(1));
  });

  test(
    'a failed move is counted and reported, and the batch continues',
    () async {
      // file9 has no source, so its action fails while the rest succeed.
      final actions = [for (var i = 0; i < _count; i++) _action(i)];
      File(p.join(base.path, 'flat', 'file9.mkv')).deleteSync();
      final c = _controller(actions);

      await c.start();

      expect(c.done, _count - 1);
      expect(c.failed, 1);
      expect(c.status, ApplyStatus.done);
      expect(c.result.hasFailures, isTrue);
      expect(c.result.failures.single.source, actions[9].source);
      expect(actions[9].status, ActionStatus.failed);
      expect(actions[9].error, isNotNull);
    },
  );

  test('pause freezes the batch and resume finishes it', () async {
    final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);

    final running = c.start();
    await _until(() => c.done >= 1);

    c.pause();
    expect(c.status, ApplyStatus.paused);
    // Let the action that was already in flight land, then prove nothing else
    // moves while paused.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final frozen = c.done;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.done, frozen);
    expect(c.status, ApplyStatus.paused);

    c.resume();
    expect(c.status, ApplyStatus.running);
    await running;

    expect(c.status, ApplyStatus.done);
    expect(c.done, _count);
  });

  test('stop halts the batch and reports what it got through', () async {
    final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);

    final running = c.start();
    await _until(() => c.done >= 1);
    c.stop();
    await running;

    expect(c.status, ApplyStatus.stopped);
    expect(c.done, lessThan(_count));
    expect(c.done, greaterThanOrEqualTo(1));
    expect(c.log.last.kind, LogKind.stopped);
    expect(c.result.succeeded, c.done);
  });

  test('stop while paused releases the gate and ends stopped', () async {
    final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);

    final running = c.start();
    await _until(() => c.done >= 1);
    c.pause();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // A stop the user issues from the paused state has to complete the gate
    // the loop is parked on, or start() never returns.
    c.stop();
    await running;

    expect(c.status, ApplyStatus.stopped);
    expect(c.done, lessThan(_count));
  });

  test('pause and resume are inert outside their own state', () async {
    final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);
    await c.start();

    c.pause();
    expect(c.status, ApplyStatus.done);
    c.resume();
    expect(c.status, ApplyStatus.done);
    c.stop();
    expect(c.status, ApplyStatus.done);
  });

  test(
    'an empty plan finishes immediately with a zero fraction guard',
    () async {
      final c = _controller(const []);

      await c.start();

      expect(c.status, ApplyStatus.done);
      expect(c.total, 0);
      expect(c.fraction, 0); // not NaN, not a divide by zero
      // No ETA once the job is terminal, and none at all when nothing moved.
      expect(c.eta, isNull);
      expect(c.log.map((e) => e.kind), [LogKind.started, LogKind.finished]);
    },
  );

  test(
    'disposing mid-batch stops the notifications but not the moves',
    () async {
      final c = _controller([for (var i = 0; i < _count; i++) _action(i)]);
      var notifications = 0;
      c.addListener(() => notifications++);

      final running = c.start();
      await _until(() => c.done >= 1);
      c.dispose();
      final atDispose = notifications;

      // The loop is not cancellable by dispose -- the files are mid-move and
      // abandoning them would be worse than finishing -- but every notify path
      // is guarded, so a disposed ChangeNotifier is never notified.
      await running;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifications, atDispose);
      expect(c.done, _count);
    },
  );
}
