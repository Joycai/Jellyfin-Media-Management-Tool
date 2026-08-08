import 'dart:convert';
import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/metadata/metadata_writer.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_merge.dart';
import 'package:jellyfin_media_management_tool/services/scrape/builtin_recipes.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_downloader.dart';
import 'package:jellyfin_media_management_tool/services/scrape/page_fetcher.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_learner.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_store.dart';
import 'package:jellyfin_media_management_tool/services/scrape/scrape_service.dart';

import '../../helpers/ai.dart';
import '../../helpers/fs.dart';

const _url = 'https://www.giga-web.jp/product/index.php?product_id=7743';

// `dart:io` is prefixed because `package:file` also exports `File`.
final _fixture = io.File(
  'test/fixtures/giga_product_7743.html',
).readAsStringSync();

/// Minimal but valid JPEG-looking payload, large enough to clear the
/// tracking-pixel guard.
final _jpeg = <int>[0xFF, 0xD8, 0xFF, ...List.filled(2000, 0x41)];

/// Serves the fixture for the product page and a JPEG for anything else.
/// Records what was asked for so header behaviour can be asserted.
class _Site {
  final List<http.Request> requests = [];

  MockClient client({int status = 200}) => MockClient((request) async {
    requests.add(request);
    if (request.url.path.endsWith('index.php')) {
      return http.Response.bytes(
        utf8.encode(_fixture),
        status,
        headers: {'content-type': 'text/html; charset=utf-8'},
        request: request,
      );
    }
    return http.Response.bytes(
      _jpeg,
      200,
      headers: {'content-type': 'image/jpeg'},
      request: request,
    );
  });
}

ScrapeService _service(_Site site, {FileSystem? fs, int status = 200}) =>
    ScrapeService(
      // minIntervalMs: 0 keeps the politeness delay out of the test clock.
      fetcher: PageFetcher(
        client: site.client(status: status),
        minIntervalMs: 0,
      ),
      recipes: RecipeStore(),
      writer: MetadataWriter(fs: fs ?? newMemoryFs()),
    );

void main() {
  group('scrapeUrl', () {
    test('produces complete metadata from the built-in recipe', () async {
      final site = _Site();
      final result = await _service(site).scrapeUrl(_url);

      expect(result.scraped.title, '美少女戦士セーラーディオーレ 絶望の餌食');
      expect(result.scraped.code, 'SPSF-43');
      expect(result.scraped.runtimeMinutes, 85);
      expect(result.scraped.premiered, '2026-08-14');
      expect(result.scraped.genres, hasLength(11));
      expect(result.scraped.actors.single.name, '西元めいさ');
      expect(result.recipe, isNotNull);
    });

    test('walks the age gate, then asks for the page', () async {
      final site = _Site();
      await _service(site).scrapeUrl(_url);

      // Two requests, in this order. The flag cookie on its own means nothing
      // to this site: it only counts on a session that has been through the
      // gate, which is what the first request is for.
      expect(site.requests.map((r) => r.url.path).toList(), [
        '/cookie_set.php',
        '/product/index.php',
      ]);

      final headers = site.requests.last.headers;
      expect(headers['Cookie'], contains('old_check=yes'));
      expect(headers['Cookie'], contains('layout=jpn'));
      expect(headers['User-Agent'], contains('Mozilla/5.0'));
      expect(headers['Accept-Language'], 'ja,en;q=0.8');
      // A product request with no referer is answered with a redirect to the
      // front page, so this header is load-bearing, not decoration.
      expect(headers['Referer'], 'https://www.giga-web.jp/top.php');
    });

    test(
      'does not report a site-wide OpenGraph note when it is skipped',
      () async {
        // The GIGA recipe sets skipStructuredData, so tier 1 never runs and
        // there is nothing to warn about.
        final result = await _service(_Site()).scrapeUrl(_url);
        expect(result.notes, isEmpty);
      },
    );

    test('derives a backdrop from the first sample still', () async {
      final result = await _service(_Site()).scrapeUrl(_url);
      expect(result.scraped.fanartUrl, result.scraped.extraFanartUrls.first);
      expect(result.scraped.origins[MetadataField.fanart], FieldOrigin.derived);
    });

    test('rejects a malformed URL before touching the network', () async {
      final site = _Site();
      await expectLater(
        _service(site).scrapeUrl('not a url'),
        throwsA(isA<PageFetchException>()),
      );
      expect(site.requests, isEmpty);
    });

    test('surfaces an HTTP error', () async {
      await expectLater(
        _service(_Site(), status: 503).scrapeUrl(_url),
        throwsA(isA<PageFetchException>()),
      );
    });
  });

  group('tier 3 — the LLM learns a recipe', () {
    // A host with no built-in recipe, served the same fixture markup.
    const unknownUrl = 'https://unknown.example/product/index.php?id=1';

    test('is not reached while a recipe already matches', () async {
      final provider = ScriptedProvider([BuiltinRecipes.gigaWebJson]);
      final result = await _service(
        _Site(),
      ).scrapeUrl(_url, learner: RecipeLearner(provider));

      // The built-in GIGA recipe handles this page, so a healthy site never
      // pays for a model call.
      expect(provider.calls, 0);
      expect(result.learnedRecipe, isNull);
    });

    test(
      'runs when nothing matches, and does not save what it learns',
      () async {
        final recipes = RecipeStore();
        final provider = ScriptedProvider([BuiltinRecipes.gigaWebJson]);
        final service = ScrapeService(
          fetcher: PageFetcher(client: _Site().client(), minIntervalMs: 0),
          recipes: recipes,
          writer: MetadataWriter(fs: newMemoryFs()),
        );

        final result = await service.scrapeUrl(
          unknownUrl,
          learner: RecipeLearner(provider),
        );

        expect(provider.calls, 1);
        expect(result.learnedRecipe, isNotNull);
        expect(result.scraped.code, 'SPSF-43');
        expect(result.notes, contains(ScrapeNote.recipeLearned));
        // The whole point: a recipe the model invented reaches the store only
        // after a human confirms it in the preview.
        expect(recipes.learned, isEmpty);
      },
    );

    test('reports a note when the model cannot work the page out', () async {
      final provider = ScriptedProvider([
        '{"fields":{"title":{"selector":"#nope"}}}',
      ]);
      final result = await _service(
        _Site(),
      ).scrapeUrl(unknownUrl, learner: RecipeLearner(provider));

      expect(provider.calls, RecipeLearner.maxAttempts);
      expect(result.learnedRecipe, isNull);
      expect(result.notes, contains(ScrapeNote.recipeLearningFailed));
    });

    test('stays on the free tiers when no learner is supplied', () async {
      final result = await _service(_Site()).scrapeUrl(unknownUrl);

      expect(result.learnedRecipe, isNull);
      expect(result.notes, contains(ScrapeNote.noRecipe));
      expect(result.notes, isNot(contains(ScrapeNote.recipeLearningFailed)));
    });
  });

  group('folder refresh', () {
    /// An NFO carrying the provenance comment `NfoWriter` leaves behind.
    String nfoWithSource(String title, String url) =>
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<movie><title>$title</title><!-- scraped from $url --></movie>';

    test('finds only the NFOs that record where they came from', () async {
      final fs = newMemoryFs();
      seedFile(fs, '/work/a/a.nfo', contents: nfoWithSource('A', _url));
      seedFile(fs, '/work/b/b.nfo', contents: nfoWithSource('B', _url));
      // Written by some other tool: no source comment, so nothing to go back to.
      seedFile(
        fs,
        '/work/c/c.nfo',
        contents: '<movie><title>C</title></movie>',
      );
      seedFile(fs, '/work/d/notes.txt', contents: 'ignore me');
      seedFile(fs, '/work/.hidden/h.nfo', contents: nfoWithSource('H', _url));

      final targets = await _service(
        _Site(),
        fs: fs,
      ).findRescrapeTargets('/work');

      expect(targets.map((t) => t.title), containsAll(['A', 'B']));
      expect(targets.map((t) => t.title), isNot(contains('C')));
      expect(targets.map((t) => t.title), isNot(contains('H')));
      expect(targets.first.sourceUrl, _url);
    });

    test('refreshes each title with the safe defaults', () async {
      final fs = newMemoryFs();
      seedFile(
        fs,
        '/work/a/a.nfo',
        contents:
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<movie><title>My Own Title</title><playcount>7</playcount>'
            '<!-- scraped from $_url --></movie>',
      );
      final service = _service(_Site(), fs: fs);
      final targets = await service.findRescrapeTargets('/work');

      final progress = <int>[];
      final result = await service.rescrapeAll(
        targets,
        onProgress: (done, _) => progress.add(done),
      );

      expect(result.succeeded, 1);
      expect(result.hasFailures, isFalse);
      expect(progress, [1]);

      final nfo = fs.file('/work/a/a.nfo').readAsStringSync();
      // Conflict kept, blank filled, unmanaged element carried through.
      expect(nfo, contains('My Own Title'));
      expect(nfo, contains('<runtime>85</runtime>'));
      expect(nfo, contains('<playcount>7</playcount>'));
    });

    test('downloads no artwork by default', () async {
      final fs = newMemoryFs();
      seedFile(fs, '/work/a/a.nfo', contents: nfoWithSource('A', _url));
      final site = _Site();
      final service = _service(site, fs: fs);

      await service.rescrapeAll(await service.findRescrapeTargets('/work'));

      // The page (and the age gate in front of it), but nothing for images —
      // which is the actual claim, so assert that rather than a bare count.
      expect(site.requests.where((r) => r.url.path.endsWith('.jpg')), isEmpty);
      expect(fs.file('/work/a/poster.jpg').existsSync(), isFalse);
    });

    test('one bad title does not sink the batch', () async {
      final fs = newMemoryFs();
      seedFile(fs, '/work/a/a.nfo', contents: nfoWithSource('A', _url));
      seedFile(fs, '/work/b/b.nfo', contents: nfoWithSource('B', 'not-a-url'));
      final service = _service(_Site(), fs: fs);

      final result = await service.rescrapeAll(
        await service.findRescrapeTargets('/work'),
      );

      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(result.failures.keys.single, contains('b.nfo'));
    });

    test('collects undo bookkeeping across the whole batch', () async {
      final fs = newMemoryFs();
      seedFile(fs, '/work/a/a.nfo', contents: nfoWithSource('A', _url));
      seedFile(fs, '/work/b/b.nfo', contents: nfoWithSource('B', _url));
      final service = _service(_Site(), fs: fs);

      final result = await service.rescrapeAll(
        await service.findRescrapeTargets('/work'),
        backupDir: '/undo/blobs/op-1',
      );

      // Both NFOs existed, so both are restorable rather than created — one
      // manifest covers the operation the user thinks of as one action.
      expect(result.restored, hasLength(2));
      expect(result.created, isEmpty);
    });
  });

  group('scrapeHtml (paste fallback)', () {
    test(
      'takes the same path as a live fetch, with no network at all',
      () async {
        final site = _Site();
        final result = await _service(
          site,
        ).scrapeHtml(_fixture, sourceUrl: _url);
        expect(site.requests, isEmpty);
        expect(result.scraped.code, 'SPSF-43');
        expect(result.scraped.genres, hasLength(11));
      },
    );

    test('requires a source URL so relative links can be resolved', () async {
      await expectLater(
        _service(_Site()).scrapeHtml(_fixture, sourceUrl: ''),
        throwsA(isA<PageFetchException>()),
      );
    });
  });

  group('existing NFO', () {
    test('is read back and turned into a merge plan', () async {
      final fs = newMemoryFs();
      seedFile(
        fs,
        '/work/SPSF-43.nfo',
        contents: '''
<?xml version="1.0" encoding="utf-8"?>
<movie>
  <title>My Own Title</title>
  <genre>Tokusatsu</genre>
  <playcount>7</playcount>
</movie>
''',
      );

      final result = await _service(
        _Site(),
        fs: fs,
      ).scrapeUrl(_url, targetDir: '/work', nfoFileName: 'SPSF-43.nfo');

      expect(result.existing, isNotNull);
      expect(result.existing!.title, 'My Own Title');
      // Conflicting scalar -> keep; blank field -> fill; list -> merge.
      expect(
        result.mergePlan.decisionFor(MetadataField.title),
        MergeDecision.keep,
      );
      expect(
        result.mergePlan.decisionFor(MetadataField.code),
        MergeDecision.replace,
      );
      expect(
        result.mergePlan.decisionFor(MetadataField.genres),
        MergeDecision.merge,
      );
      expect(result.merged.title, 'My Own Title');
      expect(result.merged.code, 'SPSF-43');
      expect(result.merged.genres.first, 'Tokusatsu');
      expect(result.merged.genres, hasLength(12));
    });
  });

  group('commit', () {
    test('writes the NFO and the selected artwork', () async {
      final fs = newMemoryFs();
      final site = _Site();
      final service = _service(site, fs: fs);
      final result = await service.scrapeUrl(_url);

      final written = await service.commit(
        metadata: result.merged,
        pageUrl: result.pageUrl,
        targetDir: '/work',
        nfoFileName: 'SPSF-43.nfo',
        recipe: result.recipe,
        images: ImageSelection.posterOnly,
      );

      expect(written.hasFailures, isFalse);
      final nfo = fs.file('/work/SPSF-43.nfo').readAsStringSync();
      expect(
        nfo,
        contains('<title>SPSF43 美少女戦士セーラーディオーレ 絶望の餌食 (2026)</title>'),
      );
      expect(nfo, contains('<runtime>85</runtime>'));
      expect(nfo, contains('<studio>GIGA</studio>'));
      expect(nfo, contains('<poster>poster.jpg</poster>'));
      expect(fs.file('/work/poster.jpg').existsSync(), isTrue);
    });

    test('sends the page as Referer when downloading images', () async {
      final site = _Site();
      final service = _service(site, fs: newMemoryFs());
      final result = await service.scrapeUrl(_url);
      await service.commit(
        metadata: result.merged,
        pageUrl: result.pageUrl,
        targetDir: '/work',
        nfoFileName: 'a.nfo',
        recipe: result.recipe,
        images: ImageSelection.posterOnly,
      );

      final imageRequest = site.requests.last;
      expect(imageRequest.headers['Referer'], _url);
    });

    test('backs up an NFO it is about to replace', () async {
      final fs = newMemoryFs();
      seedFile(
        fs,
        '/work/a.nfo',
        contents: '<movie><title>Old</title></movie>',
      );
      final service = _service(_Site(), fs: fs);
      final result = await service.scrapeUrl(_url);

      final written = await service.commit(
        metadata: result.merged,
        pageUrl: result.pageUrl,
        targetDir: '/work',
        nfoFileName: 'a.nfo',
        images: ImageSelection.posterOnly,
        backupDir: '/undo/op-1',
      );

      expect(
        fs.file('/undo/op-1/a.nfo').readAsStringSync(),
        contains('<title>Old</title>'),
      );
      expect(written.restorablePaths.keys, contains('/work/a.nfo'));
    });

    test(
      'carries unmanaged elements of the old NFO through the rewrite',
      () async {
        final fs = newMemoryFs();
        seedFile(
          fs,
          '/work/a.nfo',
          contents: '<movie><title>Old</title><playcount>7</playcount></movie>',
        );
        final service = _service(_Site(), fs: fs);
        final result = await service.scrapeUrl(_url);
        await service.commit(
          metadata: result.merged,
          pageUrl: result.pageUrl,
          targetDir: '/work',
          nfoFileName: 'a.nfo',
          images: ImageSelection.posterOnly,
        );

        expect(
          fs.file('/work/a.nfo').readAsStringSync(),
          contains('<playcount>7</playcount>'),
        );
      },
    );

    test('an image that fails to download does not fail the NFO', () async {
      final fs = newMemoryFs();
      final service = ScrapeService(
        fetcher: PageFetcher(
          minIntervalMs: 0,
          client: MockClient((request) async {
            if (request.url.path.endsWith('index.php')) {
              return http.Response.bytes(
                utf8.encode(_fixture),
                200,
                headers: {'content-type': 'text/html; charset=utf-8'},
              );
            }
            return http.Response('nope', 404);
          }),
        ),
        writer: MetadataWriter(fs: fs),
      );
      final result = await service.scrapeUrl(_url);
      final written = await service.commit(
        metadata: result.merged,
        pageUrl: result.pageUrl,
        targetDir: '/work',
        nfoFileName: 'a.nfo',
      );

      expect(written.hasFailures, isFalse);
      expect(fs.file('/work/a.nfo').existsSync(), isTrue);
      expect(fs.file('/work/poster.jpg').existsSync(), isFalse);
      // No artwork downloaded -> no <art> block promising files that are not
      // there.
      expect(
        fs.file('/work/a.nfo').readAsStringSync(),
        isNot(contains('<art>')),
      );
    });
  });

  group('ImageDownloader', () {
    test('names files from their magic number, not the URL', () {
      expect(ImageDownloader.extensionFor([0xFF, 0xD8, 0xFF, 0x00]), 'jpg');
      expect(
        ImageDownloader.extensionFor([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]),
        'png',
      );
      expect(
        ImageDownloader.extensionFor([
          ...'RIFF'.codeUnits,
          0, 0, 0, 0, //
          ...'WEBP'.codeUnits,
        ]),
        'webp',
      );
      expect(ImageDownloader.extensionFor([0x00]), 'jpg');
    });

    test('defaults to a handful of stills, not all of them', () {
      const selection = ImageSelection();
      expect(selection.resolveExtra(31), hasLength(5));
      expect(ImageSelection.posterOnly.resolveExtra(31), isEmpty);
      expect(const ImageSelection(extraFanart: {0, 7}).resolveExtra(31), {
        0,
        7,
      });
    });
  });
}
