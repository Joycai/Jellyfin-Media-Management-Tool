import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/ai_service.dart';
import 'package:jellyfin_media_management_tool/services/file_browser_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/file_browser/media_columns.dart';
import 'package:jellyfin_media_management_tool/widgets/file_browser/media_table.dart';
import 'package:provider/provider.dart';

/// Records what the table asks the settings to persist, and counts reads of
/// one value only [MediaTable.build] looks at.
///
/// The read counter is the rebuild probe: nothing here notifies, so the count
/// moves only when the table's own build method runs again.
class _ProbeSettings extends SettingsService {
  final List<Map<MediaColumn, double>> commits = [];
  int resets = 0;
  int tableBuilds = 0;

  @override
  bool get showVideoThumbnails {
    tableBuilds++;
    return super.showVideoThumbnails;
  }

  /// Last committed weights, kept here rather than in the real service.
  ///
  /// Deliberately not calling super: the real setters arm a 250ms `config.json`
  /// save timer that would outlive the test. This stands in for the persisted
  /// state — same stable-identity contract the real getter now has, so
  /// `context.select` behaves the same.
  Map<MediaColumn, double>? _committed;

  @override
  Map<MediaColumn, double> get columnWeights =>
      _committed ?? super.columnWeights;

  @override
  void setColumnWeights(Map<MediaColumn, double> weights) {
    commits.add(Map.of(weights));
    _committed = MediaColumnLayout.sanitize(weights);
    notifyListeners();
  }

  @override
  void resetColumnWeights() {
    resets++;
    _committed = null;
    notifyListeners();
  }
}

const _resizeTooltip = 'Drag to resize · double-click to reset';

double _headerWidth(WidgetTester tester, String label) => tester
    .widget<SizedBox>(
      find
          .ancestor(of: find.text(label), matching: find.byType(SizedBox))
          .first,
    )
    .width!;

Future<(_ProbeSettings, FileBrowserService)> _pumpTable(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dir = Directory.systemTemp.createTempSync('media_table_test');
  File('${dir.path}${Platform.pathSeparator}alpha.txt').writeAsStringSync('a');
  File('${dir.path}${Platform.pathSeparator}beta.txt').writeAsStringSync('bb');
  addTearDown(() => dir.deleteSync(recursive: true));

  final settings = _ProbeSettings();
  final browser = FileBrowserService();
  addTearDown(browser.dispose);

  // Real directory I/O: it only completes outside the fake-async zone the
  // widget binding installs, so the listing has to be awaited in runAsync
  // before the first frame rather than settled into afterwards.
  await tester.runAsync(() async {
    browser.setCurrentDirectory(dir.path);
    await browser.loadFiles();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<AiService>.value(value: AiService()),
        ChangeNotifierProvider<FileBrowserService>.value(value: browser),
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
          body: MediaTable(
            searchQuery: '',
            onOrganize: () {},
            onPickFolder: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('alpha.txt'), findsOneWidget, reason: 'folder did not load');
  return (settings, browser);
}

void main() {
  testWidgets('a column drag is local until the pointer is released', (
    tester,
  ) async {
    final (settings, _) = await _pumpTable(tester);
    final before = _headerWidth(tester, 'NAME');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip(_resizeTooltip).first),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();

    // The columns have moved on screen...
    expect(_headerWidth(tester, 'NAME'), lessThan(before));
    // ...without notifying every listener in the app, or re-arming the
    // config.json write, once per pointer move.
    expect(settings.commits, isEmpty);

    await gesture.up();
    // The divider also carries a double-tap (reset widths), whose recognizer
    // leaves a countdown running after the pointer lifts. Let it expire, or
    // the test ends with a timer pending.
    await tester.pump(const Duration(milliseconds: 400));
    expect(settings.commits, hasLength(1));
    expect(
      settings.commits.single[MediaColumn.name],
      lessThan(MediaColumnLayout.defaults[MediaColumn.name]!),
    );
  });

  testWidgets('a cancelled drag keeps the width it left on screen', (
    tester,
  ) async {
    final (settings, _) = await _pumpTable(tester);
    final before = _headerWidth(tester, 'NAME');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip(_resizeTooltip).first),
    );
    // Two moves: the first is spent crossing the touch slop, so the recognizer
    // only starts reporting updates on the second.
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    final dragged = _headerWidth(tester, 'NAME');
    expect(dragged, lessThan(before), reason: 'drag never took effect');

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 400));

    expect(settings.commits, hasLength(1), reason: 'cancel must still commit');
    expect(_headerWidth(tester, 'NAME'), dragged, reason: 'must not snap back');
  });

  testWidgets('selecting a row does not rebuild the table', (tester) async {
    final (settings, _) = await _pumpTable(tester);
    final before = settings.tableBuilds;

    await tester.tap(find.text('alpha.txt'));
    await tester.pumpAndSettle();

    // The row and the footer track the selection through their own narrow
    // subscriptions; the table — and with it every other visible row — does
    // not run its build method at all.
    expect(settings.tableBuilds, before);
    expect(find.text('1 selected · 2 items'), findsOneWidget);
  });

  testWidgets('a directory change does rebuild the table', (tester) async {
    // The counterpart: narrowing the subscriptions must not have narrowed
    // them past the point of noticing new contents.
    final (settings, browser) = await _pumpTable(tester);
    final before = settings.tableBuilds;

    final other = Directory.systemTemp.createTempSync('media_table_test2');
    File(
      '${other.path}${Platform.pathSeparator}gamma.txt',
    ).writeAsStringSync('g');
    addTearDown(() => other.deleteSync(recursive: true));

    await tester.runAsync(() async {
      browser.setCurrentDirectory(other.path);
      await browser.loadFiles();
    });
    await tester.pumpAndSettle();

    expect(settings.tableBuilds, greaterThan(before));
    expect(find.text('gamma.txt'), findsOneWidget);
    expect(find.text('alpha.txt'), findsNothing);
  });
}
