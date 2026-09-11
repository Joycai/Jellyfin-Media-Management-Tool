import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/dialogs/input_dialog.dart';

/// InputDialog backs the file rename and the scrape pane's free-text fields.
/// The behaviour worth pinning is the maxLines split: above one line the field
/// is a text area where Enter inserts a newline instead of confirming.
void main() {
  testWidgets('the action button returns the field', (tester) async {
    String? result;
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
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const InputDialog(
                    title: 'Rename',
                    labelText: 'New name',
                    initialValue: 'before.mkv',
                    actionLabel: 'Go',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The initial value is preselected in the field, so replacing it is what
    // a rename dialog has to get right.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'before.mkv',
    );
    await tester.enterText(find.byType(TextField), 'after.mkv');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Go'));
    await tester.pumpAndSettle();

    expect(result, 'after.mkv');
  });

  testWidgets('Enter confirms a single-line field', (tester) async {
    String? result;
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
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const InputDialog(
                    title: 'Rename',
                    labelText: 'New name',
                    actionLabel: 'Go',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'typed.mkv');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result, 'typed.mkv');
  });

  testWidgets('a multi-line field keeps Enter as a newline', (tester) async {
    String? result;
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
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const InputDialog(
                    title: 'Synopsis',
                    labelText: 'Text',
                    actionLabel: 'Go',
                    maxLines: 5,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'two\nparagraphs');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pumpAndSettle();

    // Still open: a synopsis is several paragraphs long and Enter must not
    // commit it half written.
    expect(result, isNull);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Go'));
    await tester.pumpAndSettle();
    expect(result, 'two\nparagraphs');
  });

  testWidgets('cancel returns null', (tester) async {
    var returned = false;
    String? result = 'untouched';
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
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const InputDialog(
                    title: 'Rename',
                    labelText: 'New name',
                    actionLabel: 'Go',
                  ),
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);
  });
}
