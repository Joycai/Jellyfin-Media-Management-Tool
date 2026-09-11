import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/file_browser/file_context_menu.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// deleteEntries is the destructive path shared by the file context menu and
/// the Delete shortcut, and it was at 0% coverage. It deletes real files
/// through dart:io, so these run against a temp directory.
late Directory base;
late FileBrowserService browser;

FileEntry _file(String name) {
  final f = File(p.join(base.path, name))..writeAsStringSync('x');
  return FileEntry(
    path: f.path,
    isDirectory: false,
    size: 1,
    modified: DateTime(2026),
  );
}

FileEntry _dir(String name) {
  final d = Directory(p.join(base.path, name))..createSync();
  File(p.join(d.path, 'inner.mkv')).writeAsStringSync('y');
  return FileEntry(
    path: d.path,
    isDirectory: true,
    size: 0,
    modified: DateTime(2026),
  );
}

/// Pumps a host whose button runs [deleteEntries] with the given entries, then
/// taps it so the confirmation dialog is on screen.
Future<void> _pumpAndOpen(WidgetTester tester, List<FileEntry> entries) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<FileBrowserService>.value(
      value: browser,
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
              onPressed: () => deleteEntries(context, entries),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pump();
  // The deletes are real dart:io calls and a widget test's fake clock does not
  // deliver their completions, so the event loop has to be run for real.
  // Pumping between rounds is what lets each continuation land: deleteEntries
  // awaits the deletions one after another, and a single runAsync window is not
  // enough for a batch of more than one.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    base = Directory.systemTemp.createTempSync('file_context_menu_');
    browser = FileBrowserService();
  });

  tearDown(() {
    browser.dispose();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  testWidgets('an empty selection is a no-op and asks nothing', (tester) async {
    await _pumpAndOpen(tester, const []);

    // Returns before the dialog is built, so there is nothing to dismiss.
    expect(find.widgetWithText(FilledButton, 'Delete'), findsNothing);
    expect(find.textContaining('cannot be undone'), findsNothing);
  });

  testWidgets('cancelling deletes nothing', (tester) async {
    final f = _file('a.mkv');
    await _pumpAndOpen(tester, [f]);

    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await _cancel(tester);

    expect(File(f.path).existsSync(), isTrue);
    expect(find.textContaining('Deleted'), findsNothing);
  });

  testWidgets('confirming deletes one file and reports the count', (
    tester,
  ) async {
    final f = _file('a.mkv');
    await _pumpAndOpen(tester, [f]);

    // The single-item wording names the file, because "delete 1 items" does
    // not tell you which one you are about to lose.
    expect(find.textContaining('a.mkv'), findsOneWidget);
    await _confirm(tester);

    expect(File(f.path).existsSync(), isFalse);
    expect(find.textContaining('Deleted 1'), findsOneWidget);
  });

  testWidgets('a directory goes recursively', (tester) async {
    final d = _dir('Show');
    final inner = p.join(d.path, 'inner.mkv');
    await _pumpAndOpen(tester, [d]);
    await _confirm(tester);

    expect(File(inner).existsSync(), isFalse);
    expect(Directory(d.path).existsSync(), isFalse);
  });

  testWidgets('a mixed batch deletes everything and clears the selection', (
    tester,
  ) async {
    final a = _file('a.mkv');
    final b = _file('b.mkv');
    final d = _dir('Show');
    // No setCurrentDirectory here: it would start a real directory watcher on
    // the temp folder, which is not what this test is about and which on
    // Windows keeps a handle that the recursive delete below then trips over.
    browser.toggleSelection(a);
    browser.toggleSelection(b);
    browser.toggleSelection(d);
    expect(browser.selectionCount, 3);

    await _pumpAndOpen(tester, [a, b, d]);
    expect(find.textContaining('3 selected items'), findsOneWidget);
    await _confirm(tester);

    expect(File(a.path).existsSync(), isFalse);
    expect(File(b.path).existsSync(), isFalse);
    expect(Directory(d.path).existsSync(), isFalse);
    expect(browser.selectionCount, 0);
    expect(find.textContaining('Deleted 3'), findsOneWidget);
  });

  testWidgets('one failure is reported without aborting the rest', (
    tester,
  ) async {
    final missing = FileEntry(
      path: p.join(base.path, 'gone.mkv'),
      isDirectory: false,
      size: 1,
      modified: DateTime(2026),
    );
    final real = _file('real.mkv');

    await _pumpAndOpen(tester, [missing, real]);
    await _confirm(tester);

    // The batch counts what it managed and surfaces the first error, rather
    // than stopping at the entry that failed.
    expect(File(real.path).existsSync(), isFalse);
    expect(find.textContaining('Delete failed'), findsOneWidget);
  });
}
