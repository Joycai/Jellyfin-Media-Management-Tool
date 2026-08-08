import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_cache.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_downloader.dart';
import 'package:jellyfin_media_management_tool/services/metadata/metadata_writer.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_role.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_fetcher.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';

import '../../helpers/fs.dart';

final _jpeg = <int>[0xFF, 0xD8, 0xFF, ...List.filled(2000, 0x41)];
final _referer = Uri.parse('https://e.test/product/1');

class _Host {
  final List<Uri> requests = [];
  final Set<String> missing;

  _Host({this.missing = const {}});

  MockClient get client => MockClient((request) async {
    requests.add(request.url);
    if (missing.contains(request.url.path)) return http.Response('', 404);
    return http.Response.bytes(
      _jpeg,
      200,
      headers: {'content-type': 'image/jpeg'},
    );
  });

  PageFetcher get fetcher => PageFetcher(client: client, minIntervalMs: 0);
}

void main() {
  test('fetches each URL once, however many times it is asked', () async {
    final host = _Host();
    final cache = ScrapeImageCache(fetcher: host.fetcher, referer: _referer);

    await cache.load('https://e.test/a.jpg');
    await cache.load('https://e.test/a.jpg');
    await Future.wait([
      cache.load('https://e.test/b.jpg'),
      cache.load('https://e.test/b.jpg'),
    ]);

    expect(host.requests, hasLength(2));
    expect(cache.loadedCount, 2);
  });

  test('a failure is remembered, not retried', () async {
    // Artwork is never load-bearing. A dead URL should cost one request and
    // then show a broken tile, not one request per rebuild.
    final host = _Host(missing: {'/gone.jpg'});
    final cache = ScrapeImageCache(fetcher: host.fetcher, referer: _referer);

    await cache.load('https://e.test/gone.jpg');
    await cache.load('https://e.test/gone.jpg');

    expect(host.requests, hasLength(1));
    expect(cache.isFailed('https://e.test/gone.jpg'), isTrue);
    expect(cache.peek('https://e.test/gone.jpg'), isNull);
  });

  test('the write reuses what the grid already downloaded', () async {
    // The whole justification for showing thumbnails at all. Without this,
    // drawing a grid of thirty stills and then writing three of them would
    // cost thirty-three fetches against a rate-limited host.
    final host = _Host();
    final fetcher = host.fetcher;
    final cache = ScrapeImageCache(fetcher: fetcher, referer: _referer);

    await cache.loadAll([
      'https://e.test/poster.jpg',
      'https://e.test/still-1.jpg',
    ]);
    expect(host.requests, hasLength(2));

    final metadata = MediaMetadata(
      posterUrl: 'https://e.test/poster.jpg',
      extraFanartUrls: ['https://e.test/still-1.jpg'],
    );
    final assets = await ImageDownloader(fetcher).download(
      metadata,
      referer: _referer,
      selection: const ImageSelection(fanart: false),
      cache: cache,
    );

    expect(assets, hasLength(2));
    expect(assets.first.bytes, _jpeg);
    // Still two: the commit went to the cache, not back to the site.
    expect(host.requests, hasLength(2));
  });

  test('an image the grid never loaded is still downloaded', () async {
    final host = _Host();
    final fetcher = host.fetcher;
    final cache = ScrapeImageCache(fetcher: fetcher, referer: _referer);

    final assets = await ImageDownloader(fetcher).download(
      MediaMetadata(posterUrl: 'https://e.test/poster.jpg'),
      referer: _referer,
      selection: const ImageSelection(fanart: false),
      cache: cache,
    );

    expect(assets, hasLength(1));
    expect(host.requests, hasLength(1));
  });

  test('loadAll stops when the panel goes away', () async {
    final host = _Host();
    final cache = ScrapeImageCache(fetcher: host.fetcher, referer: _referer);

    var loaded = 0;
    await cache.loadAll(
      ['https://e.test/1.jpg', 'https://e.test/2.jpg', 'https://e.test/3.jpg'],
      onProgress: () => loaded++,
      isCancelled: () => loaded >= 2,
    );

    expect(host.requests, hasLength(2));
  });

  group('saveImages', () {
    test('writes the pictures and leaves the NFO alone', () async {
      // The whole reason Save exists as its own operation: putting images in a
      // folder must not be able to rewrite metadata.
      final fs = newMemoryFs();
      seedFile(
        fs,
        '/work/SPSF-43.nfo',
        contents: '<movie><title>Mine</title></movie>',
      );
      final host = _Host();
      final service = ScrapeService(
        fetcher: host.fetcher,
        writer: MetadataWriter(fs: fs),
      );

      final written = await service.saveImages(
        imageNames: const {
          'https://e.test/pac_s.jpg': 'poster.jpg',
          'https://e.test/01.jpg': 'spsf43_01.jpg',
        },
        targetDir: '/work',
        referer: _referer,
      );

      expect(written.succeeded, 2);
      expect(fs.file('/work/poster.jpg').existsSync(), isTrue);
      expect(fs.file('/work/spsf43_01.jpg').existsSync(), isTrue);
      // Untouched, byte for byte.
      expect(
        fs.file('/work/SPSF-43.nfo').readAsStringSync(),
        '<movie><title>Mine</title></movie>',
      );
    });

    test('a name that escapes the folder is refused, not written', () async {
      final fs = newMemoryFs();
      final host = _Host();
      final service = ScrapeService(
        fetcher: host.fetcher,
        writer: MetadataWriter(fs: fs),
      );

      final written = await service.saveImages(
        imageNames: const {'https://e.test/a.jpg': '../escaped.jpg'},
        targetDir: '/work',
        referer: _referer,
      );

      expect(written.succeeded, 0);
      expect(written.hasFailures, isTrue);
      expect(fs.file('/escaped.jpg').existsSync(), isFalse);
    });

    test('an unreachable image costs the batch nothing else', () async {
      final fs = newMemoryFs();
      final host = _Host(missing: {'/gone.jpg'});
      final service = ScrapeService(
        fetcher: host.fetcher,
        writer: MetadataWriter(fs: fs),
      );

      final written = await service.saveImages(
        imageNames: const {
          'https://e.test/gone.jpg': 'poster.jpg',
          'https://e.test/ok.jpg': 'fanart.jpg',
        },
        targetDir: '/work',
        referer: _referer,
      );

      expect(written.succeeded, 1);
      expect(fs.file('/work/fanart.jpg').existsSync(), isTrue);
    });

    test('the roles the user assigned decide the file names', () async {
      final fs = newMemoryFs();
      final host = _Host();
      final service = ScrapeService(
        fetcher: host.fetcher,
        writer: MetadataWriter(fs: fs),
      );

      final names = ImageNaming.plan(
        order: const ['https://e.test/a.jpg', 'https://e.test/db/b.jpg'],
        selected: const {'https://e.test/a.jpg', 'https://e.test/db/b.jpg'},
        roles: const {'https://e.test/a.jpg': ImageRole.landscape},
        extensionOf: (_) => 'jpg',
      );
      await service.saveImages(
        imageNames: names,
        targetDir: '/work',
        referer: _referer,
      );

      expect(fs.file('/work/landscape.jpg').existsSync(), isTrue);
      // Unmarked, so it kept the server's own name.
      expect(fs.file('/work/b.jpg').existsSync(), isTrue);
    });
  });
}
