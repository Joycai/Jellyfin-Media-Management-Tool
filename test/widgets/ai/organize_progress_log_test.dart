import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';
import 'package:jellyfin_media_management_tool/services/organize/apply_controller.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/ai/organize_progress_screen.dart';
import 'package:provider/provider.dart';

/// An empty plan: `start` logs exactly two INFO lines and touches no disk, so
/// the log panel can be driven without a filesystem.
ApplyController _controller() => ApplyController(
  plan: OrganizePlan(
    mediaType: 'movie',
    targetRoot: 'Movies',
    reasoning: const [],
    actions: const [],
  ),
  baseDir: '/work',
  backup: false,
  totalBytes: 0,
);

Future<void> _pump(WidgetTester tester, ApplyController c) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ApplyController>.value(
      value: c,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        theme: AppTheme.light(),
        home: const OrganizeProgressScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump();
}

/// The log's own rows, scoped to the terminal so a similarly worded header
/// cannot be mistaken for one.
Finder _logRows(String fragment) => find.descendant(
  of: find.byType(ListView),
  matching: find.textContaining(fragment),
);

void main() {
  testWidgets('the terminal shows what the job logged', (tester) async {
    final c = _controller();
    await _pump(tester, c);

    expect(c.logLength, 2);
    expect(_logRows('Started'), findsOneWidget);
    expect(_logRows('organized'), findsOneWidget);
  });

  testWidgets('filtering a level re-syncs the log instead of appending to it', (
    tester,
  ) async {
    final c = _controller();
    await _pump(tester, c);
    expect(_logRows('Started'), findsOneWidget);

    // Both surviving entries are INFO, so switching it off empties the panel.
    // A sync that only ever appended would leave them on screen.
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    expect(_logRows('Started'), findsNothing);
    expect(_logRows('organized'), findsNothing);

    // And switching it back has to find them again, from a rewound cursor.
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    expect(_logRows('Started'), findsOneWidget);
    expect(_logRows('organized'), findsOneWidget);
  });
}
