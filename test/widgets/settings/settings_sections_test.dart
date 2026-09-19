import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_about_section.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_controls.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_paths_section.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_privacy_section.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_shortcuts_section.dart';
import 'package:provider/provider.dart';

/// Layout smoke tests for the 06-Config pages.
///
/// These pages are wide two-column grids inside a scrolling page, which is the
/// shape where a stray `CrossAxisAlignment.stretch` or an `Expanded` under an
/// unbounded constraint throws during layout — and a layout throw blanks the
/// whole page while the app's console stays silent. Cheap to catch here.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
        ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('paths lays out, and says what it cannot do yet', (tester) async {
    await _pump(tester, const PathsSection());

    expect(tester.takeException(), isNull);
    expect(find.text('Library roots'), findsOneWidget);
    expect(find.text('Favorite paths'), findsOneWidget);
    // The roots block is drawn to spec and then labelled, never dropped.
    expect(find.text('Coming soon'), findsNWidgets(2));
  });

  testWidgets('paths is a 2x2 grid whose two columns share row tracks', (
    tester,
  ) async {
    await _pump(tester, const PathsSection());

    // Artboard 21 is one CSS grid, not two stacked columns: the cards in a row
    // share a track, so their tops and bottoms line up and the two columns end
    // level. Stacking each column on its own gets the first row right by luck
    // and everything below it wrong.
    final cards = [
      for (var i = 0; i < 4; i++)
        tester.getRect(find.byType(SettingsCard).at(i)),
    ];
    final [roots, favorites, defaults, recent] = cards;

    expect(roots.top, moreOrLessEquals(favorites.top, epsilon: 0.5));
    expect(roots.height, moreOrLessEquals(favorites.height, epsilon: 0.5));
    expect(defaults.top, moreOrLessEquals(recent.top, epsilon: 0.5));
    expect(defaults.height, moreOrLessEquals(recent.height, epsilon: 0.5));
    expect(defaults.top - roots.bottom, moreOrLessEquals(AppSpacing.lg));
    // Left column wider than the right: the design's `1.12fr 1fr`.
    expect(roots.width, greaterThan(favorites.width));

    // Every group label sits inside its own card, not floating above it.
    for (final (label, card) in [
      ('Library roots', roots),
      ('Favorite paths', favorites),
      ('Default locations', defaults),
      ('Recent', recent),
    ]) {
      expect(
        card.contains(tester.getRect(find.text(label)).topLeft),
        isTrue,
        reason: '$label should be drawn inside its card',
      );
    }
  });

  testWidgets('privacy lays out with no disk behind it', (tester) async {
    await _pump(tester, const PrivacySection());

    // `getApplicationSupportDirectory` has no plugin here, and the page must
    // still render — the cache sizes are diagnostics, not load-bearing.
    expect(tester.takeException(), isNull);
    expect(find.text('Caches'), findsOneWidget);
    expect(find.text('Danger zone'), findsOneWidget);
  });

  testWidgets('privacy is the same 2x2 grid, on equal columns', (tester) async {
    await _pump(tester, const PrivacySection());

    final cards = [
      for (var i = 0; i < 4; i++)
        tester.getRect(find.byType(SettingsCard).at(i)),
    ];
    final [locations, privacy, caches, danger] = cards;

    expect(locations.top, moreOrLessEquals(privacy.top, epsilon: 0.5));
    expect(locations.height, moreOrLessEquals(privacy.height, epsilon: 0.5));
    expect(caches.top, moreOrLessEquals(danger.top, epsilon: 0.5));
    expect(caches.height, moreOrLessEquals(danger.height, epsilon: 0.5));
    // 22 is `1fr 1fr`, unlike 21.
    expect(locations.width, moreOrLessEquals(privacy.width, epsilon: 0.5));

    for (final (label, card) in [
      ('Config & data', locations),
      ('Privacy', privacy),
      ('Caches', caches),
      ('Danger zone', danger),
    ]) {
      expect(
        card.contains(tester.getRect(find.text(label)).topLeft),
        isTrue,
        reason: '$label should be drawn inside its card',
      );
    }
  });

  testWidgets('shortcuts renders every binding, and the search filters', (
    tester,
  ) async {
    await _pump(tester, const ShortcutsSection());

    expect(tester.takeException(), isNull);
    expect(find.text('Rename the focused file'), findsOneWidget);
    // 23 draws each group label inside its own card.
    expect(
      tester
          .getRect(find.byType(SettingsCard).first)
          .contains(tester.getRect(find.text('Navigation')).topLeft),
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'rename');
    await tester.pump();

    expect(find.text('Rename the focused file'), findsOneWidget);
    // A command that does not match is gone, groups and all.
    expect(find.text('Select every file in the list'), findsNothing);
  });

  testWidgets('about splits the version into name and build', (tester) async {
    await _pump(tester, const AboutSection(version: '1.2.3+45'));

    expect(tester.takeException(), isNull);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    // Commit, branch and commit time are not stamped into the build yet, so
    // they read as em dashes with a footnote rather than quietly disappearing.
    expect(find.text('—'), findsNWidgets(3));
    // The design's own third-party list has nowhere to open yet, so the row is
    // drawn and labelled rather than dropped.
    expect(find.text('Third-party licenses'), findsOneWidget);
    // One system row, not a separate card for OS and architecture.
    expect(find.text('System'), findsOneWidget);
    // Artboard 24 puts the two info cards in one grid row, so they match
    // height; the build-info note lives inside its card for that reason.
    final build = tester.getRect(find.byType(SettingsCard).at(0));
    final source = tester.getRect(find.byType(SettingsCard).at(1));
    expect(build.height, moreOrLessEquals(source.height, epsilon: 0.5));
    // 24 puts every group label inside its own card, not floating above it.
    expect(
      build.contains(tester.getRect(find.text('Build info')).topLeft),
      isTrue,
    );
    expect(
      source.contains(tester.getRect(find.text('Open source')).topLeft),
      isTrue,
    );
  });
}
