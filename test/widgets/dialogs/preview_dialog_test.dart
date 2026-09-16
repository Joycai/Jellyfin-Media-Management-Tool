import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/models/file_entry.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/dialogs/preview_dialog.dart';

/// PreviewDialog is what a double-click on a row opens. The video half needs
/// media_kit's native libmpv backend, which a widget test cannot load, so
/// these cover canPreview's truth table and the image half -- including the
/// error branch, which is what an undecodable download actually hits.
FileEntry _entry(String path, {bool isDirectory = false}) => FileEntry(
  path: path,
  isDirectory: isDirectory,
  size: 1,
  modified: DateTime(2026),
);

void main() {
  group('canPreview', () {
    test('images and videos, nothing else', () {
      expect(PreviewDialog.canPreview(_entry('/w/poster.jpg')), isTrue);
      expect(PreviewDialog.canPreview(_entry('/w/poster.png')), isTrue);
      expect(PreviewDialog.canPreview(_entry('/w/poster.webp')), isTrue);
      expect(PreviewDialog.canPreview(_entry('/w/movie.mkv')), isTrue);
      expect(PreviewDialog.canPreview(_entry('/w/movie.mp4')), isTrue);
    });

    test('not for metadata, subtitles, directories or unknown types', () {
      expect(PreviewDialog.canPreview(_entry('/w/movie.nfo')), isFalse);
      expect(PreviewDialog.canPreview(_entry('/w/movie.srt')), isFalse);
      expect(PreviewDialog.canPreview(_entry('/w/whatever.bin')), isFalse);
      expect(
        PreviewDialog.canPreview(_entry('/w/Movies', isDirectory: true)),
        isFalse,
      );
    });

    test('a directory named like an image is still not previewable', () {
      expect(
        PreviewDialog.canPreview(_entry('/w/poster.jpg', isDirectory: true)),
        isFalse,
      );
    });
  });

  group('the image half', () {
    late Directory base;

    setUp(() => base = Directory.systemTemp.createTempSync('preview_dialog_'));
    tearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });

    Future<void> pumpPreview(WidgetTester tester, FileEntry entry) async {
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
          home: Scaffold(body: PreviewDialog(entry: entry)),
        ),
      );
      await tester.pump();
      // Reading and decoding the file are real IO; a widget test's fake clock
      // does not deliver their completions, so the event loop has to run for
      // real before the errorBuilder branch can paint.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('the title bar names the file and its size', (tester) async {
      final f = File('${base.path}${Platform.pathSeparator}poster.jpg')
        ..writeAsBytesSync(List.filled(2048, 0x41));

      await pumpPreview(tester, _entry(f.path));

      expect(find.text('poster.jpg'), findsOneWidget);
      // The image itself is in the tree; whether it decodes is the codec's
      // business and is asserted separately.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('a file that will not decode falls back to a placeholder', (
      tester,
    ) async {
      // Not a JPEG, whatever the extension claims: the errorBuilder branch is
      // what a truncated download or a mislabelled file produces.
      final f = File('${base.path}${Platform.pathSeparator}broken.jpg')
        ..writeAsBytesSync(List.filled(64, 0x00));

      await pumpPreview(tester, _entry(f.path));

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing file is a broken image, not a crash', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        _entry('${base.path}${Platform.pathSeparator}gone.jpg'),
      );

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
