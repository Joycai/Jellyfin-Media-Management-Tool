import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/dialogs/title_hint_dialog.dart';

/// The gate in front of every AI organize run: the user says whether the
/// folder is a movie, a series or "work it out", and optionally types a title.
/// Assertions go through the returned TitleHintResult rather than through
/// localized strings, so the suite does not depend on the ARB wording.
Future<void> _pump(
  WidgetTester tester,
  void Function(Future<TitleHintResult?>) capture,
) async {
  await tester.pumpWidget(
    MaterialApp(
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
          // ElevatedButton, not TextButton: the dialog's own actions are two
          // TextButtons, and a TextButton host would shift the indexes the
          // Cancel and Skip tests tap by one.
          builder: (context) => ElevatedButton(
            onPressed: () => capture(
              showTitleHintDialog(context, folderName: 'Dune.2021.1080p'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The three kind chips are identified by icon, which the ARB wording cannot
/// change underneath the test.
Finder _chip(IconData icon) =>
    find.descendant(of: find.byType(ChoiceChip), matching: find.byIcon(icon));

void main() {
  testWidgets('auto is the default and a typed title comes back with it', (
    tester,
  ) async {
    TitleHintResult? result;
    await _pump(tester, (f) => f.then((r) => result = r));

    expect(_chip(Icons.auto_awesome), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Dune Part Two  ');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.kind, MediaKindHint.auto);
    // Trimmed, because the model gets this string verbatim.
    expect(result!.title, 'Dune Part Two');
  });

  testWidgets('picking movie or series is what reaches the model', (
    tester,
  ) async {
    TitleHintResult? result;
    await _pump(tester, (f) => f.then((r) => result = r));

    await tester.tap(_chip(Icons.movie_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result!.kind, MediaKindHint.movie);
    expect(result!.title, isEmpty);
  });

  testWidgets('series is its own hint', (tester) async {
    TitleHintResult? result;
    await _pump(tester, (f) => f.then((r) => result = r));

    await tester.tap(_chip(Icons.live_tv_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The Expanse');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result!.kind, MediaKindHint.series);
    expect(result!.title, 'The Expanse');
  });

  testWidgets('Skip returns a result with no title', (tester) async {
    TitleHintResult? result;
    await _pump(tester, (f) => f.then((r) => result = r));

    await tester.enterText(find.byType(TextField), 'ignored');
    // Cancel is the first TextButton, Skip the second, Analyze the FilledButton.
    await tester.tap(find.byType(TextButton).at(1));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.title, isEmpty);
    expect(result!.kind, MediaKindHint.auto);
  });

  testWidgets('Cancel returns null so the caller aborts', (tester) async {
    var returned = false;
    TitleHintResult? result = TitleHintResult(
      kind: MediaKindHint.movie,
      title: 'sentinel',
    );
    await _pump(
      tester,
      (f) => f.then((r) {
        result = r;
        returned = true;
      }),
    );

    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);
  });

  testWidgets('Enter in the field submits', (tester) async {
    TitleHintResult? result;
    await _pump(tester, (f) => f.then((r) => result = r));

    await tester.enterText(find.byType(TextField), 'Arrival');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.title, 'Arrival');
  });
}
