import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/history_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/model_parameters_page.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_about_section.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_paths_section.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_privacy_section.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_controls.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_shortcuts_section.dart';
import 'package:jellyfin_media_management_tool/widgets/ui/app_controls.dart';
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

  testWidgets('privacy lays out with no disk behind it', (tester) async {
    await _pump(tester, const PrivacySection());

    // `getApplicationSupportDirectory` has no plugin here, and the page must
    // still render — the cache sizes are diagnostics, not load-bearing.
    expect(tester.takeException(), isNull);
    expect(find.text('Caches'), findsOneWidget);
    expect(find.text('Danger zone'), findsOneWidget);
  });

  testWidgets('shortcuts renders every binding, and the search filters', (
    tester,
  ) async {
    await _pump(tester, const ShortcutsSection());

    expect(tester.takeException(), isNull);
    expect(find.text('Rename the focused file'), findsOneWidget);

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

  testWidgets('the model parameters page lays out', (tester) async {
    final maxOutput = TextEditingController();
    addTearDown(maxOutput.dispose);
    await _pump(
      tester,
      ModelParametersPage(
        serviceName: 'Local',
        model: 'qwen3-8b',
        contextWindow: 131072,
        onContextWindow: (_) {},
        maxOutput: maxOutput,
        onMaxOutputChanged: () {},
        detectedCeiling: null,
        onCollapse: () {},
        onSave: () {},
        sampling: const SizedBox.shrink(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('131,072'), findsOneWidget);
    // The tick labels read in k/M, while the field keeps raw tokens.
    expect(find.text('128k'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
  });

  testWidgets('the header actions sit flush with the content edge', (
    tester,
  ) async {
    final maxOutput = TextEditingController();
    addTearDown(maxOutput.dispose);
    await _pump(
      tester,
      ModelParametersPage(
        serviceName: 'OpenAI',
        model: 'gpt-4o-mini',
        contextWindow: 131072,
        onContextWindow: (_) {},
        maxOutput: maxOutput,
        onMaxOutputChanged: () {},
        detectedCeiling: null,
        onCollapse: () {},
        onSave: () {},
        sampling: const SizedBox.shrink(),
      ),
    );

    // 03b puts Collapse + Save against the right edge, on the same 24px inset
    // as the cards below. A `Flexible` breadcrumb beside a `Spacer` split the
    // free space between them and left the group stranded 38px short, which
    // reads as a misplaced button rather than as a layout bug.
    final save = tester.getRect(find.widgetWithText(AppButton, 'Save'));
    final collapse = tester.getRect(find.widgetWithText(AppButton, 'Collapse'));
    final card = tester.getRect(find.byType(SettingsCard).at(1));
    expect(save.right, moreOrLessEquals(card.right, epsilon: 0.5));
    expect(save.left - collapse.right, moreOrLessEquals(AppSpacing.sm));
    expect(save.height, AppSizes.controlSm);

    // 03b's two columns are grid cells: same row, same height. The right card
    // holds one field and would otherwise stop well short of the slider card.
    final left = tester.getRect(find.byType(SettingsCard).first);
    expect(card.height, moreOrLessEquals(left.height, epsilon: 0.5));
  });
}
