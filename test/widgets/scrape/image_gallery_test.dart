import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/l10n/app_localizations.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_cache.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_fetcher.dart';
import 'package:jellyfin_media_management_tool/theme/app_theme.dart';
import 'package:jellyfin_media_management_tool/widgets/scrape/image_gallery.dart';

/// Same stand-in bytes the cache tests use: a JPEG header and filler. It never
/// decodes, so every tile paints its placeholder -- which is fine here, because
/// what is under test is the size the tile *asks* to decode at, not the pixels.
final _jpeg = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  ...List.filled(2000, 0x41),
]);
final _referer = Uri.parse('https://e.test/product/1');
const _url = 'https://e.test/poster.jpg';

/// A column 320 wide, the narrowest the picker is ever drawn in.
const _panelWidth = 320.0;

ScrapeImageCache _cache() => ScrapeImageCache(
  fetcher: PageFetcher(
    client: MockClient(
      (request) async => http.Response.bytes(
        _jpeg,
        200,
        headers: {'content-type': 'image/jpeg'},
      ),
    ),
    minIntervalMs: 0,
  ),
  referer: _referer,
);

Future<void> _pumpGallery(WidgetTester tester, ScrapeImageCache cache) async {
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
        body: Center(
          child: SizedBox(
            width: _panelWidth,
            child: SingleChildScrollView(
              child: ImageGallery(
                images: const [GalleryImage(url: _url, label: 'Poster')],
                selected: const {_url},
                cache: cache,
                roles: const {},
                plannedNames: const {},
                onToggle: (_, _) {},
                onRole: (_, _) {},
                onSelectAll: () {},
                onSelectNone: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a loaded tile decodes at display size, not source size', (
    tester,
  ) async {
    final cache = _cache();
    await cache.load(_url);
    expect(cache.peek(_url), isNotNull);

    await _pumpGallery(tester, cache);

    final finder = find.byType(Image);
    expect(finder, findsOneWidget);
    final image = tester.widget<Image>(finder);

    // Without cacheWidth this is a bare MemoryImage and the whole 1000x1500
    // poster is decoded for a tile a third of a panel wide.
    expect(
      image.image,
      isA<ResizeImage>(),
      reason: 'the tile must downscale on decode, not paint a full-size bitmap',
    );
    final resize = image.image as ResizeImage;

    final shown = tester.getSize(finder);
    final ratio = MediaQuery.devicePixelRatioOf(tester.element(finder));
    expect(resize.width, (shown.width * ratio).round());
    expect(
      resize.height,
      isNull,
      reason: 'a height would squash the aspect ratio BoxFit.cover relies on',
    );
    // The artwork this stands in for is a ~1000px poster. The tile is a third
    // of a panel column, so at any device pixel ratio the decode target has to
    // land well under the source; if it ever reaches source size again the
    // downscale has stopped earning its keep.
    expect(resize.width!, lessThan(1000));
  });

  testWidgets('a tile with nothing cached yet paints no image at all', (
    tester,
  ) async {
    await _pumpGallery(tester, _cache());

    expect(find.byType(Image), findsNothing);
  });
}
