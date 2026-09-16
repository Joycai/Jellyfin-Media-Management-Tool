import 'dart:io';

import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/task_service.dart';
import 'package:jellyfin_media_management_tool/services/transfer/file_clipboard.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/file_browser/file_transfer_flow.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_controls.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// The paste flow is the only place the file browser's clipboard touches
/// disk, so it runs here against a real temp directory, the way the delete
/// flow's tests do.
late Directory base;
late FileBrowserService browser;
late FileClipboard clipboard;
late TaskService tasks;
late HistoryService history;

FileEntry _file(String rel, {String contents = 'x'}) {
  final f = File(p.join(base.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
  return FileEntry(
    path: f.path,
    isDirectory: false,
    size: contents.length,
    modified: DateTime(2026),
  );
}

String _dest() {
  final d = Directory(p.join(base.path, 'dest'))..createSync();
  return d.path;
}

/// Pumps a host whose button runs [action], then taps it.
Future<void> _pumpAndRun(
  WidgetTester tester,
  Future<void> Function(BuildContext) action,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FileBrowserService>.value(value: browser),
        ChangeNotifierProvider<FileClipboard>.value(value: clipboard),
        ChangeNotifierProvider<TaskService>.value(value: tasks),
        ChangeNotifierProvider<HistoryService>.value(value: history),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => action(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('go'));
  await _settleIo(tester);
}

/// Real dart:io calls only complete outside the fake clock, and each pump
/// between rounds lets one more continuation land. A paste chains a dozen or
/// so awaits (plan, transfer, undo manifest), so it takes many short rounds.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    base = Directory.systemTemp.createTempSync('file_transfer_flow_');
    browser = FileBrowserService();
    clipboard = FileClipboard();
    tasks = TaskService();
    history = HistoryService(
      fs: const LocalFileSystem(),
      undoDir: p.join(base.path, 'undo'),
    );
  });

  tearDown(() {
    browser.dispose();
    clipboard.dispose();
    tasks.dispose();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  testWidgets('copy fills the clipboard and touches nothing', (tester) async {
    final a = _file('a.mkv');
    await _pumpAndRun(tester, (ctx) async => copyEntries(ctx, [a]));

    expect(clipboard.paths, [a.path]);
    expect(clipboard.mode, ClipboardMode.copy);
    expect(find.text('1 items copied'), findsOneWidget);
    expect(File(a.path).existsSync(), isTrue);
  });

  testWidgets('an empty clipboard pastes nothing and starts no task', (
    tester,
  ) async {
    final dest = _dest();
    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: dest),
    );

    expect(tasks.tasks, isEmpty);
  });

  testWidgets('pasting a cut moves the file, clears the clipboard and '
      'records an undo entry', (tester) async {
    final a = _file('a.mkv', contents: 'video');
    final dest = _dest();
    clipboard.set([a.path], ClipboardMode.cut);

    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: dest),
    );

    expect(clipboard.isEmpty, isTrue);
    expect(File(p.join(dest, 'a.mkv')).readAsStringSync(), 'video');
    expect(File(a.path).existsSync(), isFalse);
    expect(tasks.tasks.single.kind, TaskKind.transfer);
    expect(tasks.tasks.single.status, TaskStatus.done);
    expect(history.entries.single.moves.single['to'], p.join(dest, 'a.mkv'));
    expect(find.text('Moved 1 items'), findsOneWidget);
  });

  testWidgets('a copy stays on the clipboard after pasting', (tester) async {
    final a = _file('a.mkv');
    final dest = _dest();
    clipboard.set([a.path], ClipboardMode.copy);

    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: dest),
    );

    expect(clipboard.paths, [a.path]);
    expect(File(p.join(dest, 'a.mkv')).existsSync(), isTrue);
    expect(File(a.path).existsSync(), isTrue);
  });

  testWidgets('a name conflict asks first; cancel moves nothing', (
    tester,
  ) async {
    final a = _file('a.mkv', contents: 'new');
    final dest = _dest();
    File(p.join(dest, 'a.mkv')).writeAsStringSync('old');
    clipboard.set([a.path], ClipboardMode.cut);

    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: dest),
    );

    expect(find.text('1 items already exist in dest'), findsOneWidget);
    expect(find.text('→ a (2).mkv'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settleIo(tester);

    expect(tasks.tasks, isEmpty);
    expect(File(a.path).existsSync(), isTrue);
    expect(File(p.join(dest, 'a.mkv')).readAsStringSync(), 'old');
    // A cancelled paste is not a consumed cut.
    expect(clipboard.isCut(a.path), isTrue);
  });

  testWidgets('keep both never overwrites the existing file', (tester) async {
    final a = _file('a.mkv', contents: 'new');
    final dest = _dest();
    File(p.join(dest, 'a.mkv')).writeAsStringSync('old');
    clipboard.set([a.path], ClipboardMode.copy);

    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: dest),
    );
    await tester.tap(find.widgetWithText(AppButton, 'Keep both'));
    await _settleIo(tester);

    expect(File(p.join(dest, 'a.mkv')).readAsStringSync(), 'old');
    expect(File(p.join(dest, 'a (2).mkv')).readAsStringSync(), 'new');
  });

  testWidgets('skip existing leaves the conflict alone and says so', (
    tester,
  ) async {
    final a = _file('a.mkv', contents: 'new');
    final dest = _dest();
    File(p.join(dest, 'a.mkv')).writeAsStringSync('old');
    clipboard.set([a.path], ClipboardMode.copy);

    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: dest),
    );
    await tester.tap(find.widgetWithText(AppButton, 'Skip existing'));
    await _settleIo(tester);

    expect(File(p.join(dest, 'a.mkv')).readAsStringSync(), 'old');
    expect(File(p.join(dest, 'a (2).mkv')).existsSync(), isFalse);
    expect(find.text('Copied 0 items'), findsOneWidget);
  });

  testWidgets('a folder pasted into itself is refused with a message', (
    tester,
  ) async {
    _file('Show/e1.mkv');
    final show = p.join(base.path, 'Show');
    clipboard.set([show], ClipboardMode.cut);

    await _pumpAndRun(
      tester,
      (ctx) => pasteClipboard(ctx, destinationDir: show),
    );

    expect(tasks.tasks, isEmpty);
    expect(find.text('A folder cannot be pasted into itself'), findsOneWidget);
    expect(File(p.join(show, 'e1.mkv')).existsSync(), isTrue);
  });
}
