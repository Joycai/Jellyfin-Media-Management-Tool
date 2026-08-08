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
///   3. ask the LLM to learn a recipe, when a [RecipeLearner] is supplied and
///      nothing matched. The result is **returned, never stored** — see
///      [RecipeLearner] for why that has to be a human's call;
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
import 'recipe_learner.dart';
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

  /// No recipe existed, so the LLM wrote one. It is not saved yet.
  recipeLearned,

  /// The LLM was asked for a recipe and could not produce a working one.
  recipeLearningFailed,

  /// The site sent us somewhere else — typically an age gate or its front
  /// page. Whatever was extracted describes that page, not the title, so this
  /// is the note to show before any other.
  redirectedAway,
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

  /// Set when tier 3 ran and produced something usable. **Not in
  /// `RecipeStore`** — the preview offers to remember it, and only the user's
  /// confirmation puts it there.
  final ScrapeRecipe? learnedRecipe;

  const ScrapeResult({
    required this.scraped,
    required this.existing,
    required this.mergePlan,
    required this.pageUrl,
    required this.recipe,
    required this.notes,
    this.learnedRecipe,
  });

  /// Metadata as it would be written if the user changed nothing.
  MediaMetadata get merged => NfoMerge.resolve(existing, scraped, mergePlan);
}

/// One NFO on disk that records where it was scraped from, and so can be
/// refreshed without asking the user for the URL again.
class RescrapeTarget {
  final String targetDir;
  final String nfoFileName;
  final String sourceUrl;

  /// Title as the NFO currently has it, for the confirmation list.
  final String? title;

  const RescrapeTarget({
    required this.targetDir,
    required this.nfoFileName,
    required this.sourceUrl,
    this.title,
  });

  String get label => title ?? nfoFileName;
}

/// What a folder-wide refresh did. Counts, not the first error — a batch that
/// stops at the first bad page is worse than useless.
class BatchScrapeResult {
  final int succeeded;

  /// NFO path -> what went wrong.
  final Map<String, String> failures;

  /// Undo bookkeeping merged across every title in the batch, so one manifest
  /// covers the whole operation rather than one per title.
  final List<String> created;
  final Map<String, String> restored;

  const BatchScrapeResult({
    required this.succeeded,
    required this.failures,
    required this.created,
    required this.restored,
  });

  int get failed => failures.length;
  bool get hasFailures => failures.isNotEmpty;
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
  /// [learner] enables tier 3 for pages no recipe matches; omit it to stay on
  /// the free tiers.
  Future<ScrapeResult> scrapeUrl(
    String url, {
    String? targetDir,
    String? nfoFileName,
    AiCancelToken? cancelToken,
    RecipeLearner? learner,
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
        redirectedAway: page.wasRedirected,
        targetDir: targetDir,
        nfoFileName: nfoFileName,
        learner: learner,
        cancelToken: cancelToken,
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
    RecipeLearner? learner,
    AiCancelToken? cancelToken,
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
      learner: learner,
      cancelToken: cancelToken,
    );
  }

  Future<ScrapeResult> _extract({
    required String html,
    required Uri pageUrl,
    required ScrapeRecipe? recipe,
    required bool degradedEncoding,
    bool redirectedAway = false,
    String? targetDir,
    String? nfoFileName,
    RecipeLearner? learner,
    AiCancelToken? cancelToken,
  }) async {
    final document = html_parser.parse(html);
    final notes = <ScrapeNote>[];
    // First, because it explains every other disappointing thing about the
    // result: we are parsing a page the user never asked for.
    if (redirectedAway) notes.add(ScrapeNote.redirectedAway);
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
    ScrapeRecipe? learned;
    if (recipe == null) {
      notes.add(ScrapeNote.noRecipe);
      // Tier 3 — only reached when tier 2 had nothing to run, so a healthy
      // site never pays for a model call.
      if (learner != null) {
        final result = await learner.learn(
          html: html,
          document: document,
          pageUrl: pageUrl,
          cancelToken: cancelToken,
        );
        if (result == null) {
          notes.add(ScrapeNote.recipeLearningFailed);
        } else {
          learned = result.recipe;
          notes.add(ScrapeNote.recipeLearned);
          metadata.fillFrom(result.extracted, overwrite: true);
        }
      }
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
      recipe: recipe ?? learned,
      notes: notes,
      learnedRecipe: learned,
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

  /// Every title under [rootDir] that can be refreshed without asking for a
  /// URL — i.e. whose NFO still carries the `scraped from` comment this app
  /// wrote.
  ///
  /// An NFO from another tool has no such comment and is simply not a
  /// candidate; there is nothing to guess from and inventing a search would be
  /// a different feature.
  Future<List<RescrapeTarget>> findRescrapeTargets(
    String rootDir, {
    int limit = 400,
  }) async {
    final out = <RescrapeTarget>[];
    for (final path in await writer.findNfoFiles(rootDir, limit: limit)) {
      final dir = writer.fs.path.dirname(path);
      final name = writer.fs.path.basename(path);
      final xml = await writer.readExisting(dir, name);
      if (xml == null) continue;
      final existing = NfoReader.read(xml);
      final url = existing?.sourceUrl;
      if (url == null || url.isEmpty) continue;
      out.add(
        RescrapeTarget(
          targetDir: dir,
          nfoFileName: name,
          sourceUrl: url,
          title: existing?.title,
        ),
      );
    }
    return out;
  }

  /// Refreshes every target in turn, applying each one's **default** merge
  /// plan — blanks filled, conflicts kept, lists merged.
  ///
  /// There is no per-title preview here and that is the point: 300 dialogs is
  /// not review, it is a fatigue test. The gate is the confirmation shown
  /// before the batch starts, and the defaults are the conservative ones, so
  /// the worst case is that a title gains information it was missing.
  ///
  /// Deliberately serial. `PageFetcher` enforces a per-host minimum interval
  /// anyway, so parallelism here would only queue up inside the fetcher while
  /// making the progress bar lie about what is happening.
  Future<BatchScrapeResult> rescrapeAll(
    List<RescrapeTarget> targets, {
    ImageSelection images = ImageSelection.none,
    String? backupDir,
    AiCancelToken? cancelToken,
    void Function(int done, int total)? onProgress,
  }) async {
    var succeeded = 0;
    final failures = <String, String>{};
    final created = <String>[];
    final restored = <String, String>{};

    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      final path = writer.fs.path.join(target.targetDir, target.nfoFileName);
      try {
        cancelToken?.throwIfCancelled();
        final result = await scrapeUrl(
          target.sourceUrl,
          targetDir: target.targetDir,
          nfoFileName: target.nfoFileName,
          cancelToken: cancelToken,
        );
        final written = await commit(
          metadata: result.merged,
          pageUrl: result.pageUrl,
          targetDir: target.targetDir,
          nfoFileName: target.nfoFileName,
          recipe: result.recipe,
          images: images,
          backupDir: backupDir,
          cancelToken: cancelToken,
        );
        created.addAll(written.createdPaths);
        restored.addAll(written.restorablePaths);
        if (written.hasFailures) {
          failures[path] = written.failures.values.first;
        } else {
          succeeded++;
        }
      } on AiCancelled {
        rethrow;
      } catch (e) {
        failures[path] = e.toString();
      }
      onProgress?.call(i + 1, targets.length);
    }

    return BatchScrapeResult(
      succeeded: succeeded,
      failures: failures,
      created: created,
      restored: restored,
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
