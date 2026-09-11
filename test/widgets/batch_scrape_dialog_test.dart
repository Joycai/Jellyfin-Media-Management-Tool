import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_downloader.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/batch_scrape_dialog.dart';

/// The gate for a folder-wide metadata refresh. Single-title scraping gets a
/// field-level diff; a batch cannot, so this dialog is the only review the user
/// gets before three hundred NFO files are rewritten. It was at 0% coverage.
const _targets = [
  RescrapeTarget(
    targetDir: '/work/Movies/Dune',
    nfoFileName: 'movie.nfo',
    sourceUrl: 'https://e.test/p/1',
    title: 'Dune',
  ),
  RescrapeTarget(
    targetDir: '/work/Movies/Arrival',
    nfoFileName: 'movie.nfo',
    sourceUrl: 'https://e.test/p/2',
    title: 'Arrival',
  ),
];

/// Checkbox order is: one per target, then artwork, then backup.
Future<void> _open(
  WidgetTester tester,
  void Function(Future<BatchScrapeDecision?>) capture, {
  List<RescrapeTarget> targets = _targets,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
          // ElevatedButton, not TextButton: the dialog's cancel action is a
          // TextButton and would shift the index.
          builder: (context) => ElevatedButton(
            onPressed: () =>
                capture(showBatchScrapeDialog(context, targets: targets)),
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

void main() {
  testWidgets('every target starts ticked and the batch is listed', (
    tester,
  ) async {
    await _open(tester, (_) {});

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    // 2 targets + artwork + backup. Both targets and the backup start
    // ticked; artwork is opt-in.
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(4));
    expect(tester.widget<Checkbox>(boxes.at(0)).value, isTrue);
    expect(tester.widget<Checkbox>(boxes.at(1)).value, isTrue);
    expect(tester.widget<Checkbox>(boxes.at(2)).value, isFalse);
    expect(tester.widget<Checkbox>(boxes.at(3)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel writes nothing', (tester) async {
    var returned = false;
    BatchScrapeDecision? decision = const BatchScrapeDecision(
      targets: [],
      images: ImageSelection.none,
      backup: true,
    );
    await _open(
      tester,
      (f) => f.then((d) {
        decision = d;
        returned = true;
      }),
    );

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(decision, isNull);
  });

  testWidgets('start returns every target, no artwork, backup on', (
    tester,
  ) async {
    BatchScrapeDecision? decision;
    await _open(tester, (f) => f.then((d) => decision = d));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.targets, hasLength(2));
    expect(decision!.backup, isTrue);
    // Artwork is opt-in: an untouched box means metadata only.
    expect(decision!.images.poster, isFalse);
    expect(decision!.images.fanart, isFalse);
  });

  testWidgets('ticking artwork switches the image selection to poster only', (
    tester,
  ) async {
    BatchScrapeDecision? decision;
    await _open(tester, (f) => f.then((d) => decision = d));

    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(decision!.images.poster, isTrue);
    expect(decision!.images.fanart, isFalse);
  });

  testWidgets('backup can be turned off', (tester) async {
    BatchScrapeDecision? decision;
    await _open(tester, (f) => f.then((d) => decision = d));

    await tester.tap(find.byType(Checkbox).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(decision!.backup, isFalse);
  });

  testWidgets('an unticked target is left out of the batch', (tester) async {
    BatchScrapeDecision? decision;
    await _open(tester, (f) => f.then((d) => decision = d));

    await tester.tap(find.byType(Checkbox).at(0)); // Dune
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(decision!.targets, hasLength(1));
    expect(decision!.targets.single.title, 'Arrival');
  });

  testWidgets('unticking everything disables start', (tester) async {
    var returned = false;
    await _open(tester, (f) => f.then((_) => returned = true));

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();

    // A batch of nothing must not be startable: the button is disabled rather
    // than allowed to write zero files and report success.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(returned, isFalse);
  });

  testWidgets('an empty batch offers a close button and no start', (
    tester,
  ) async {
    BatchScrapeDecision? decision;
    await _open(tester, (f) => f.then((d) => decision = d), targets: const []);

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(decision, isNull);
  });
}
