import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/font_service.dart';
import 'package:jellyfin_media_management_tool/services/settings_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_controls.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/settings_font_section.dart';
import 'package:provider/provider.dart';

/// The shared building blocks and the font picker, which the settings split
/// moved into their own libraries. Every settings section is assembled out of
/// the first three, so a change to them moves the whole screen; and the font
/// picker is what decides whether the app renders in HarmonyOS Sans or MiSans.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: SettingsService()),
        ChangeNotifierProvider<FontService>.value(value: FontService()),
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
          body: SizedBox(
            width: 600,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('shared building blocks', () {
    testWidgets('a section title renders its text', (tester) async {
      await _pump(tester, const SettingsSectionTitle('Behaviour'));

      expect(find.text('Behaviour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card header keeps its badge with the label', (tester) async {
      await _pump(
        tester,
        const SettingsCardHeader(
          'Graphics',
          badge: Text('2 detected'),
          trailing: Text('Information only'),
        ),
      );

      final label = tester.getRect(find.text('Graphics'));
      final badge = tester.getRect(find.text('2 detected'));
      final hint = tester.getRect(find.text('Information only'));
      // Only the note is pushed to the far edge; the badge belongs to the
      // title and sits one gap after it.
      expect(badge.left - label.right, moreOrLessEquals(AppSpacing.md));
      expect(badge.right, lessThan(hint.left));
    });

    testWidgets('a card holds its child and honours custom padding', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsCard(padding: EdgeInsets.all(4), child: Text('inside')),
      );

      expect(find.text('inside'), findsOneWidget);
      // The glass surface is a decorated container; without it the card is
      // just a bare child and the hairline stroke goes missing.
      expect(
        find.descendant(
          of: find.byType(SettingsCard),
          matching: find.byType(Container),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the default padding is applied when none is given', (
      tester,
    ) async {
      await _pump(tester, const SettingsCard(child: Text('inside')));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(SettingsCard),
          matching: find.byType(Container),
        ),
      );
      // 1.3a 的卡片内距，不是一个就近取的数字。
      expect(container.padding, const EdgeInsets.all(AppSpacing.lg));
    });

    testWidgets('a rows card puts a hairline between rows, not around them', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsRowsCard(
          children: [
            SettingsRow(title: 'first'),
            SettingsRow(title: 'second'),
            SettingsRow(title: 'third'),
          ],
        ),
      );

      // Three rows means two dividers: a line above the first or below the
      // last would double up with the card's own border.
      expect(find.byType(SettingsRow), findsNWidgets(3));
      expect(find.byType(Divider), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a placeholder is drawn but cannot be interacted with', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        SettingsPlaceholder(
          child: SettingsMiniButton('Add root', onPressed: () => taps++),
        ),
      );

      // Drawn — the label is on screen, so the capability is visibly planned.
      expect(find.text('Add root'), findsOneWidget);
      await tester.tap(find.text('Add root'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('a divider paints without a child', (tester) async {
      await _pump(
        tester,
        const SettingsCard(
          child: Column(children: [Text('a'), SettingsDivider(), Text('b')]),
        ),
      );

      expect(find.byType(SettingsDivider), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('font picker', () {
    testWidgets('offers the three choices and marks the active one', (
      tester,
    ) async {
      await _pump(
        tester,
        const Column(
          children: [
            FontOption(choice: AppFontChoice.system),
            FontOption(choice: AppFontChoice.harmony),
            FontOption(choice: AppFontChoice.misans),
          ],
        ),
      );

      expect(find.byType(FontOption), findsNWidgets(3));
      // Two of the three labels are literal family names, not ARB strings.
      expect(find.text('HarmonyOS Sans'), findsOneWidget);
      expect(find.text('MiSans'), findsOneWidget);
      // The default choice is the system font, so exactly one card is ticked.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an undownloaded package says so rather than looking ready', (
      tester,
    ) async {
      await _pump(tester, const FontOption(choice: AppFontChoice.harmony));

      // The status line is the only thing telling the user that picking this
      // will start a download; the system option has no such line.
      expect(find.byType(FontOption), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('the system option carries no download status', (tester) async {
      await _pump(tester, const FontOption(choice: AppFontChoice.system));

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
