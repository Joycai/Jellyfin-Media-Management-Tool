/// Orchestrates one scrape: fetch -> extract -> compare with what is already
/// on disk -> hand a reviewable result to the UI.
///
/// Deliberately **not** wired into the organize pipeline. `AiService` holds a
/// single app-wide `OrganizePlan` and nulls it the moment a second analysis
/// starts; routing scrape results through it would mean a stray "Organize"
/// click could discard metadata the user had not committed yet.
///
/// The extraction ladder is (see `docs/spec/scrape-module-spec.md`):
///
///   1. structured data the page publishes (JSON-LD / OpenGraph) — free, but
///      validated against [StructuredData.isSiteWideTemplate] first;
///   2. a recipe (learned, user-edited, or built in) — free;
///   3. *(not yet implemented)* ask the LLM to learn a recipe;
///   4. the user pastes the page HTML — always available via [scrapeHtml].
library;

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/media_metadata.dart';
import '../../models/scrape_recipe.dart';
import '../ai/ai_cancel_token.dart';
import '../metadata/metadata_writer.dart';
import '../metadata/nfo_merge.dart';
import '../metadata/nfo_reader.dart';
import '../metadata/nfo_writer.dart';
import 'image_downloader.dart';
import 'page_fetcher.dart';
import 'recipe_applier.dart';
import 'recipe_store.dart';
import 'structured_data.dart';

/// Something the user should know about a scrape that still succeeded.
enum ScrapeNote {
  /// The page's OpenGraph block described the whole site, so it was ignored.
  siteWideStructuredDataIgnored,

  /// No recipe matched this domain; only structured data was available.
  noRecipe,

  /// The page charset had no codec available and the text may be lossy.
  degradedEncoding,

  /// The recipe matched but produced nothing — it has probably gone stale.
  recipeProducedNothing,
}

/// Everything the preview dialog needs.
class ScrapeResult {
  /// What the page yielded.
  final MediaMetadata scraped;

  /// What the NFO on disk already says, when there is one.
  final MediaMetadata? existing;

  /// Per-field defaults for reconciling the two.
  final NfoMergePlan mergePlan;

  /// URL the page was actually served from — relative links resolve against
  /// this, and it is the `Referer` for image downloads.
  final Uri pageUrl;

  final ScrapeRecipe? recipe;
  final List<ScrapeNote> notes;

  const ScrapeResult({
    required this.scraped,
    required this.existing,
    required this.mergePlan,
    required this.pageUrl,
    required this.recipe,
    required this.notes,
  });

  /// Metadata as it would be written if the user changed nothing.
  MediaMetadata get merged => NfoMerge.resolve(existing, scraped, mergePlan);
}

class ScrapeService extends ChangeNotifier {
  final PageFetcher fetcher;
  final RecipeStore recipes;
  final MetadataWriter writer;

  bool _isScraping = false;
  bool get isScraping => _isScraping;

  ScrapeService({
    PageFetcher? fetcher,
    RecipeStore? recipes,
    MetadataWriter? writer,
  }) : fetcher = fetcher ?? PageFetcher(),
       recipes = recipes ?? RecipeStore(),
       writer = writer ?? const MetadataWriter();

  /// Fetches [url] and extracts everything it can.
  ///
  /// [targetDir] and [nfoFileName], when given, are used to read back an
  /// existing NFO so the result carries a real merge plan instead of assuming
  /// a clean slate.
  Future<ScrapeResult> scrapeUrl(
    String url, {
    String? targetDir,
    String? nfoFileName,
    AiCancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const PageFetchException('Not a valid URL');
    }
    _isScraping = true;
    notifyListeners();
    try {
      final recipe = recipes.forUrl(uri);
      final page = await fetcher.fetch(
        uri,
        recipe: recipe,
        cancelToken: cancelToken,
      );
      return await _extract(
        html: page.html,
        pageUrl: page.url,
        recipe: recipe,
        degradedEncoding: page.degraded,
        targetDir: targetDir,
        nfoFileName: nfoFileName,
      );
    } finally {
      cancelToken?.dispose();
      _isScraping = false;
      notifyListeners();
    }
  }

  /// Tier 4: the user pasted the page source out of their browser. Same
  /// pipeline from here on, which is what makes this a real fallback rather
  /// than a separate half-working path.
  Future<ScrapeResult> scrapeHtml(
    String rawHtml, {
    required String sourceUrl,
    String? targetDir,
    String? nfoFileName,
  }) async {
    final uri = Uri.tryParse(sourceUrl.trim());
    if (uri == null || !uri.hasScheme) {
      throw const PageFetchException(
        'A source URL is required to resolve '
        'relative links in pasted HTML',
      );
    }
    return _extract(
      html: rawHtml,
      pageUrl: uri,
      recipe: recipes.forUrl(uri),
      degradedEncoding: false,
      targetDir: targetDir,
      nfoFileName: nfoFileName,
    );
  }

  Future<ScrapeResult> _extract({
    required String html,
    required Uri pageUrl,
    required ScrapeRecipe? recipe,
    required bool degradedEncoding,
    String? targetDir,
    String? nfoFileName,
  }) async {
    final document = html_parser.parse(html);
    final notes = <ScrapeNote>[];
    if (degradedEncoding) notes.add(ScrapeNote.degradedEncoding);

    final metadata = MediaMetadata(sourceUrl: pageUrl.toString());

    // Tier 1 — free, and skipped outright for sites known to publish a
    // site-wide template.
    if (recipe?.skipStructuredData != true) {
      final structured = StructuredData.inspect(document, pageUrl);
      if (structured.siteWide) {
        notes.add(ScrapeNote.siteWideStructuredDataIgnored);
      }
      final fromStructured = StructuredData.toMetadata(structured, pageUrl);
      if (fromStructured != null) metadata.fillFrom(fromStructured);
    }

    // Tier 2 — a recipe overrides structured data field by field, because a
    // selector aimed at this page beats a generic tag.
    if (recipe == null) {
      notes.add(ScrapeNote.noRecipe);
    } else {
      final fromRecipe = RecipeApplier.apply(document, recipe, pageUrl);
      if (fromRecipe.isEmpty) {
        notes.add(ScrapeNote.recipeProducedNothing);
        await recipes.recordFailure(recipe);
      } else {
        metadata.fillFrom(fromRecipe, overwrite: true);
        await recipes.recordSuccess(recipe);
      }
    }

    // A page that only offers sample stills still deserves a backdrop.
    if (metadata.fanartUrl == null && metadata.extraFanartUrls.isNotEmpty) {
      metadata.set(
        MetadataField.fanart,
        metadata.extraFanartUrls.first,
        FieldOrigin.derived,
      );
    }

    MediaMetadata? existing;
    if (targetDir != null && nfoFileName != null) {
      final xml = await writer.readExisting(targetDir, nfoFileName);
      if (xml != null) existing = NfoReader.read(xml);
    }

    return ScrapeResult(
      scraped: metadata,
      existing: existing,
      mergePlan: NfoMerge.suggest(existing, metadata),
      pageUrl: pageUrl,
      recipe: recipe,
      notes: notes,
    );
  }

  /// Downloads the selected artwork and writes the NFO plus images.
  ///
  /// [metadata] is the *reviewed* result — whatever the user ended up with in
  /// the preview, not necessarily [ScrapeResult.scraped]. Passing it
  /// explicitly is what keeps every edit in memory until this single call.
  Future<MetadataWriteResult> commit({
    required MediaMetadata metadata,
    required Uri pageUrl,
    required String targetDir,
    required String nfoFileName,
    ScrapeRecipe? recipe,
    ImageSelection images = const ImageSelection(),
    String? backupDir,
    NfoKind kind = NfoKind.movie,
    AiCancelToken? cancelToken,
    ImageProgress? onImageProgress,
  }) async {
    final assets = await ImageDownloader(fetcher).download(
      metadata,
      referer: pageUrl,
      recipe: recipe,
      selection: images,
      cancelToken: cancelToken,
      onProgress: onImageProgress,
    );

    // The NFO's <art> block must name the files we are about to write, so the
    // options are derived from what actually downloaded.
    final poster = _assetNamed(assets, 'poster');
    final fanart = _assetNamed(assets, 'fanart');
    final existingXml = await writer.readExisting(targetDir, nfoFileName);
    final xml = NfoWriter.write(
      metadata,
      existingXml: existingXml,
      kind: kind,
      options: NfoOptions(
        posterFileName: poster ?? 'poster.jpg',
        fanartFileName: fanart ?? 'fanart.jpg',
      ),
      includeArt: poster != null || fanart != null,
    );

    return writer.write(
      baseDir: targetDir,
      nfoFileName: nfoFileName,
      nfoXml: xml,
      images: assets,
      backupDir: backupDir,
    );
  }

  /// A fresh directory under `<appSupport>/undo/blobs/` for one commit's
  /// backups, or null when the app-support directory is unavailable.
  ///
  /// Lives here rather than on [MetadataWriter] because the writer may be
  /// pointed at an injected in-memory filesystem in tests, while this is a real
  /// on-disk location; the caller passes the result in as `backupDir`. A failure
  /// is not fatal — it just means the commit runs without backups.
  static Future<String?> newBackupDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      return p.join(
        support.path,
        'undo',
        'blobs',
        'scrape-${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _assetNamed(List<ImageAsset> assets, String stem) {
    for (final a in assets) {
      if (a.relativePath.startsWith('$stem.')) return a.relativePath;
    }
    return null;
  }

  @override
  void dispose() {
    fetcher.close();
    super.dispose();
  }
}
