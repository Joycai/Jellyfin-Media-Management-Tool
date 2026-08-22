/// The scrape panel: everything needed to set one scrape up, and the scrape
/// itself, in one window.
///
/// It replaces the URL dialog for single titles. The old flow asked for a URL,
/// closed, started a background task, raised a SnackBar, and asked the user to
/// click through to a second dialog — four surfaces for one intention, and the
/// hand-off between them was where a stale `BuildContext` crashed. Here the
/// work happens in front of the user and the result opens directly.
///
/// Two ways to run it, which is the whole point of the layout:
///
/// * **Process** walks the free ladder — structured data, then a recipe, then
///   a learned recipe if a backend is configured. Costs nothing on a site the
///   app already knows.
/// * **Ask the LLM directly** hands the page to the model. Costs a request and
///   the values are the model's rather than the page's, so it is the override,
///   not the default — but it is one click away when a recipe gets it wrong.
///
/// Both land in the same preview, so the compare/merge step never has to care
/// which produced the metadata.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_service_profile.dart';
import '../../services/ai/ai_cancel_token.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai_profiles_service.dart';
import '../../services/ai_service.dart';
import '../../services/scrape/cookie_store.dart';
import '../../services/scrape/direct_extractor.dart';
import '../../services/scrape/image_cache.dart';
import '../../services/scrape/recipe_learner.dart';
import '../../services/scrape/recipe_store.dart';
import '../../services/scrape/scrape_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_dialog.dart';
import '../glass/glass_segmented.dart';
import 'scrape_review_pane.dart';

/// A scrape the user reviewed and confirmed.
///
/// Returned only when they press Write; closing the panel at any stage returns
/// null and nothing has touched disk.
class ScrapePanelResult {
  final ScrapeResult result;
  final ScrapeCommitDecision decision;

  /// Bytes already fetched to draw the artwork grid, handed on so the commit
  /// writes them instead of downloading the same images a second time.
  final ScrapeImageCache cache;

  const ScrapePanelResult({
    required this.result,
    required this.decision,
    required this.cache,
  });
}

Future<ScrapePanelResult?> showScrapePanel(
  BuildContext context, {
  required String targetDir,
  required String nfoFileName,
  required String label,
  String? suggestedKeyword,
}) => showGlassDialog<ScrapePanelResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ScrapePanel(
    targetDir: targetDir,
    nfoFileName: nfoFileName,
    label: label,
    suggestedKeyword: suggestedKeyword,
  ),
);

class ScrapePanel extends StatefulWidget {
  final String targetDir;
  final String nfoFileName;
  final String label;
  final String? suggestedKeyword;

  const ScrapePanel({
    super.key,
    required this.targetDir,
    required this.nfoFileName,
    required this.label,
    this.suggestedKeyword,
  });

  @override
  State<ScrapePanel> createState() => _ScrapePanelState();
}

enum _Stage { setup, working, results }

/// Where the metadata comes from: a URL the user already has, or a web search
/// to go and find one. The second mode exists because knowing the catalogue
/// number is not the same as knowing the URL.
enum _SourceMode { url, search }

class _ScrapePanelState extends State<ScrapePanel> {
  final _url = TextEditingController();
  final _html = TextEditingController();
  final _cookies = TextEditingController();
  final _instructions = TextEditingController();
  late final _search = TextEditingController(
    text: widget.suggestedKeyword ?? '',
  );

  late String _targetDir = widget.targetDir;
  late String _nfoFileName = widget.nfoFileName;

  /// True once the user picked the NFO themselves, so the caption stops
  /// claiming it was auto-detected.
  bool _nfoChosen = false;

  String? _backendId;
  bool _showPaste = false;
  bool _showAdvanced = false;
  _SourceMode _sourceMode = _SourceMode.url;

  _Stage _stage = _Stage.setup;
  String? _error;
  AiCancelToken? _cancel;

  /// Set while a direct extraction is running, so the step list can say which
  /// of the two buttons is being honoured.
  bool _askingLlm = false;

  /// Where the running scrape currently is, for the step list. Null before the
  /// first callback fires.
  ScrapeStage? _scrapeStage;

  /// Wall-clock for the working stage's footer.
  final _elapsed = Stopwatch();

  ScrapeResult? _result;
  ScrapeImageCache? _cache;

  /// Images still to fetch for the grid. Drives the gallery's progress line.
  int _imagesPending = 0;

  /// Bumped for each new result so the review pane rebuilds from scratch when
  /// "Ask the LLM directly" replaces what it was showing.
  int _resultGeneration = 0;

  @override
  void initState() {
    super.initState();
    _backendId = context.read<AiProfilesService>().active?.id;
  }

  @override
  void dispose() {
    _url.dispose();
    _html.dispose();
    _cookies.dispose();
    _instructions.dispose();
    _search.dispose();
    _cancel?.dispose();
    super.dispose();
  }

  // ── Running ───────────────────────────────────────────────────────────────

  AiServiceProfile? get _backend {
    final profiles = context.read<AiProfilesService>().services;
    if (profiles.isEmpty) return null;
    return profiles.firstWhere(
      (s) => s.id == _backendId,
      orElse: () => profiles.first,
    );
  }

  AiProvider? _provider() {
    final config = _backend?.toAiConfig();
    if (config == null || !config.isComplete) return null;
    return AiService.providerFor(config);
  }

  Uri? _parsedUrl() {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  /// Applies the cookies typed into the panel for the length of this run.
  ///
  /// They go into the fetcher's own store rather than anywhere on disk. A
  /// cookie pasted out of a browser can be equivalent to being signed in, and
  /// persisting one is a decision that belongs to the user in Settings, not to
  /// a text field they filled in to get past a gate once.
  void _applyCookies(ScrapeService scraper, Uri url) {
    final text = _cookies.text.trim();
    if (text.isEmpty) return;
    scraper.fetcher.cookies.importAll([
      for (final pair in text.split(';'))
        if (pair.contains('='))
          NetscapeCookie(
            domain: url.host,
            includeSubdomains: false,
            path: '/',
            secureOnly: false,
            expiresAt: 0,
            name: pair.substring(0, pair.indexOf('=')).trim(),
            value: pair.substring(pair.indexOf('=') + 1).trim(),
          ),
    ]);
  }

  Future<void> _run({required bool askLlm}) async {
    final l10n = AppLocalizations.of(context)!;
    final url = _parsedUrl();
    if (url == null) {
      // A URL is required either way; if the user was on the search tab, the
      // field they must fill is on the other one.
      setState(() {
        _sourceMode = _SourceMode.url;
        _error = l10n.scrapeUrlInvalid;
      });
      return;
    }
    final provider = _provider();
    if (askLlm && provider == null) {
      setState(() => _error = l10n.scrapeBackendNone);
      return;
    }

    final scraper = context.read<ScrapeService>();
    _applyCookies(scraper, url);
    final token = AiCancelToken();

    _elapsed
      ..reset()
      ..start();

    setState(() {
      _stage = _Stage.working;
      _askingLlm = askLlm;
      _scrapeStage = null;
      _error = null;
      _cancel = token;
    });

    void onStage(ScrapeStage stage) {
      if (mounted) setState(() => _scrapeStage = stage);
    }

    try {
      final pasted = _html.text.trim();
      // Tier 3 is only offered when there is a backend to ask; without one the
      // ladder simply stops at tier 2.
      final learner = provider == null ? null : RecipeLearner(provider);
      var result = pasted.isEmpty
          ? await scraper.scrapeUrl(
              url.toString(),
              targetDir: _targetDir,
              nfoFileName: _nfoFileName,
              cancelToken: token,
              learner: askLlm ? null : learner,
              onStage: onStage,
            )
          : await scraper.scrapeHtml(
              pasted,
              sourceUrl: url.toString(),
              targetDir: _targetDir,
              nfoFileName: _nfoFileName,
              learner: askLlm ? null : learner,
              onStage: onStage,
            );

      if (askLlm) {
        // The model re-reads the fetched page, so the step list goes back to
        // "extract" — that is genuinely where the time is spent.
        if (mounted) setState(() => _scrapeStage = ScrapeStage.extracting);
        result = await scraper.askLlm(
          result: result,
          extractor: DirectExtractor(provider!),
          instructions: _instructions.text,
        );
      }

      if (!mounted) return;
      setState(() {
        _result = result;
        _resultGeneration++;
        _stage = _Stage.results;
      });
      _primeImages(scraper, result);
    } on AiCancelled {
      if (mounted) setState(() => _stage = _Stage.setup);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.setup;
          _error = e.toString();
        });
      }
    } finally {
      _elapsed.stop();
      token.dispose();
      if (mounted) _cancel = null;
    }
  }

  /// Writes the ticked images to the folder, now, without touching the NFO.
  ///
  /// Reports a count rather than the first error, like every other batch in
  /// the app, and stays on the review stage — saving pictures is not finishing
  /// with the panel.
  Future<void> _saveImages(Map<String, String> imageNames) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final scraper = context.read<ScrapeService>();
    final result = _result!;

    try {
      final written = await scraper.saveImages(
        imageNames: imageNames,
        targetDir: _targetDir,
        referer: result.pageUrl,
        recipe: result.recipe,
        imageCache: _cache,
      );
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written.hasFailures
                ? l10n.scrapeSaveImagesPartial(
                    written.succeeded,
                    written.failed,
                  )
                : l10n.scrapeSaveImagesDone(written.succeeded, _targetDir),
          ),
        ),
      );
    } catch (e) {
      if (!messenger.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// Starts fetching every image the result offers, so the grid has something
  /// to draw.
  ///
  /// Progressive and serial: `PageFetcher` holds a per-host interval, so the
  /// tiles fill in one by one rather than all at once. That is slower than a
  /// burst would be and it is the point — the alternative is hammering a site
  /// thirty times to render a preview. Nothing here blocks the user; the
  /// fields are reviewable while the pictures arrive.
  void _primeImages(ScrapeService scraper, ScrapeResult result) {
    final merged = result.merged;
    final urls = <String>{
      if (merged.posterUrl != null) merged.posterUrl!,
      if (merged.fanartUrl != null) merged.fanartUrl!,
      ...merged.extraFanartUrls,
    }.toList();

    final cache = ScrapeImageCache(
      fetcher: scraper.fetcher,
      referer: result.pageUrl,
      recipe: result.recipe,
    );
    setState(() {
      _cache = cache;
      _imagesPending = urls.length;
    });

    unawaited(
      cache.loadAll(
        urls,
        isCancelled: () => !mounted,
        onProgress: () {
          if (mounted) setState(() => _imagesPending--);
        },
      ),
    );
  }

  /// Opens a search for the keyword in the browser.
  ///
  /// Knowing the catalogue number is not the same as knowing the URL, and the
  /// panel cannot ask for one the user does not have yet. Uses the same site
  /// list they curate in Settings — there is no second table.
  Future<void> _openSearch(SearchSite site, String keyword) async {
    final lang = Localizations.localeOf(context).languageCode;
    final uri = Uri.tryParse(
      site.url
          .replaceAll('{keyword}', Uri.encodeQueryComponent(keyword))
          .replaceAll('{lang}', lang),
    );
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _browseForNfo() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: AppLocalizations.of(context)!.scrapeNfoTarget,
      initialDirectory: _targetDir,
      type: FileType.custom,
      allowedExtensions: const ['nfo'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _targetDir = p.dirname(path);
      _nfoFileName = p.basename(path);
      _nfoChosen = true;
    });
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  // Field and button metrics come from the app theme (`inputDecorationTheme`,
  // the button themes in AppTheme) — nothing here restates them, so this
  // dialog cannot drift from the rest of the app.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final reviewing = _stage == _Stage.results;
    final working = _stage == _Stage.working;

    // Not Material's dialog surface: that paints a seed-tinted opaque slab
    // that matches nothing else in the app. The glass surface blurs what is
    // behind and lets the backdrop breathe through, like every other panel.
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, available) {
          // The review table cannot lay out narrower than its final width, so
          // while the window is still growing it is laid out at that width
          // (capped to what the screen can give) and revealed by the resize
          // instead of being squeezed through the intermediate sizes.
          final reviewSize = available.constrain(const Size(1280, 860));
          return AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            // Setting a scrape up is a short form, running one is a card of
            // steps, and reviewing one is a table beside a picture grid. The
            // window grows to match rather than making the form sprawl or the
            // review cramped.
            constraints: BoxConstraints(
              maxWidth: reviewing ? 1280 : (working ? 580 : 700),
              maxHeight: reviewing ? 860 : 760,
            ),
            child: GlassDialogSurface(
              // The content swap is faster than the resize so the incoming
              // stage is already readable while the window is still settling.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: KeyedSubtree(
                  key: ValueKey(_stage),
                  child: reviewing
                      ? OverflowBox(
                          maxWidth: reviewSize.width,
                          maxHeight: reviewSize.height,
                          child: _review(),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _header(l10n, scheme),
                            const Divider(height: 1),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  18,
                                  24,
                                  18,
                                ),
                                child: working
                                    ? _working(l10n, scheme)
                                    : _setup(l10n, scheme),
                              ),
                            ),
                            const Divider(height: 1),
                            _footer(l10n, scheme),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The review stage owns its own header and footer, so the panel hands it
  /// the whole window rather than wrapping it in a second set of chrome.
  Widget _review() => ScrapeReviewPane(
    key: ValueKey(_resultGeneration),
    result: _result!,
    defaultTargetDir: _targetDir,
    defaultNfoFileName: _nfoFileName,
    cache: _cache!,
    loadingImages: _imagesPending,
    onBack: () => setState(() => _stage = _Stage.setup),
    onCancel: () => Navigator.pop(context),
    onSaveImages: _saveImages,
    onSubmit: (decision) => Navigator.pop(
      context,
      ScrapePanelResult(result: _result!, decision: decision, cache: _cache!),
    ),
  );

  Widget _header(AppLocalizations l10n, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [scheme.tertiary, scheme.primary]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.travel_explore_outlined,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.scrapePanelTitle,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, size: 18),
          visualDensity: VisualDensity.compact,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        ),
      ],
    ),
  );

  // ── Working stage ─────────────────────────────────────────────────────────

  Widget _working(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final stageIndex = switch (_scrapeStage) {
      null => 0,
      ScrapeStage.fetching => 0,
      ScrapeStage.extracting => 1,
      ScrapeStage.comparing => 2,
    };

    _StepState stateFor(int step) => step < stageIndex
        ? _StepState.done
        : step == stageIndex
        ? _StepState.active
        : _StepState.pending;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: glass.panelFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: glass.panelStroke),
            ),
            child: Column(
              children: [
                _StepRow(label: l10n.scrapeStepFetch, state: stateFor(0)),
                const SizedBox(height: 11),
                _StepRow(
                  label: _askingLlm
                      ? l10n.scrapeAskLlm
                      : l10n.scrapeStepExtract,
                  state: stateFor(1),
                ),
                const SizedBox(height: 11),
                _StepRow(label: l10n.scrapeStepCompare, state: stateFor(2)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _url.text.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Setup stage ───────────────────────────────────────────────────────────

  Widget _setup(AppLocalizations l10n, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _source(l10n, scheme),
        const SizedBox(height: 18),
        _nfoSection(l10n, scheme),
        const SizedBox(height: 18),
        _backendRow(l10n, scheme),
        const SizedBox(height: 6),
        Text(
          l10n.scrapeAskLlmHint,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _advanced(l10n, scheme),
      ],
    );
  }

  Widget _source(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final sites = context.watch<SettingsService>().searchSites;
    final keyword = widget.suggestedKeyword;
    final recipe = _parsedUrl() == null
        ? null
        : context.watch<RecipeStore>().forUrl(_parsedUrl()!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionLabel(l10n.scrapeSource),
            const SizedBox(width: 12),
            GlassSegmented<_SourceMode>(
              value: _sourceMode,
              onChanged: (m) => setState(() => _sourceMode = m),
              items: [
                GlassSegmentedItem(
                  value: _SourceMode.url,
                  label: l10n.scrapeSourceUrl,
                  icon: Icons.link_rounded,
                ),
                GlassSegmentedItem(
                  value: _SourceMode.search,
                  label: l10n.scrapeSourceSearch,
                  icon: Icons.search_rounded,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_sourceMode == _SourceMode.url) ...[
          TextField(
            controller: _url,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'https://…',
              prefixIcon: const Icon(Icons.link_rounded, size: 18),
              errorText: _error,
            ),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _run(askLlm: false),
          ),
          if (recipe != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '${l10n.scrapeRecipeName}: ${recipe.domain}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          // The strip gives way once a URL is typed: the user has the page,
          // so a shortcut for finding it is noise.
          if (_url.text.trim().isEmpty &&
              keyword != null &&
              sites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _detectedCode(l10n, scheme, keyword, sites),
          ],
        ] else ...[
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: l10n.scrapeSearchKeyword,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (sites.isEmpty)
            Text(
              l10n.scrapeSearchNoSites,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: glass.panelFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: glass.panelStroke),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final site in sites)
                    _siteButton(
                      scheme,
                      site.name,
                      _search.text.trim().isEmpty
                          ? null
                          : () => _openSearch(site, _search.text.trim()),
                    ),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
          ],
        ],
      ],
    );
  }

  /// "识别到番号 SPSF-31" plus one button per curated search site — the code
  /// was read out of the filename, so a search is one click even before any
  /// URL exists.
  Widget _detectedCode(
    AppLocalizations l10n,
    ColorScheme scheme,
    String keyword,
    List<SearchSite> sites,
  ) => Container(
    width: double.infinity,
    // 8 + 28-px buttons + 8 lands the strip on the same 44 as the URL field
    // above it, so the two read as one column of controls.
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    decoration: BoxDecoration(
      color: scheme.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        Flexible(
          child: Text(
            l10n.scrapeDetectedCode(keyword),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final site in sites)
                  _siteButton(scheme, site.name, () {
                    _openSearch(site, keyword);
                  }),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// One search-site link, sized to sit inside a 44px strip.
  Widget _siteButton(ColorScheme scheme, String name, VoidCallback? onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.open_in_new, size: 12),
        label: Text(name),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          // Derived, not written fresh: a bare TextStyle in ButtonStyle
          // replaces the theme's and silently drops the user's UI font.
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  /// Where it lands. Auto-detected from what was right-clicked, because that
  /// is right almost every time, but never a dead end.
  Widget _nfoSection(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.scrapeNfoTarget),
        const SizedBox(height: 8),
        Container(
          // 7 + 30-px button + 7 = the same 44 every field in the panel uses.
          padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
          decoration: BoxDecoration(
            color: glass.panelFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: glass.panelStroke),
          ),
          child: Row(
            children: [
              Icon(
                Icons.data_object_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.join(_targetDir, _nfoFileName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _browseForNfo,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(l10n.scrapeNfoBrowse),
              ),
            ],
          ),
        ),
        if (!_nfoChosen) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.check_rounded, size: 14, color: scheme.tertiary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  l10n.scrapeNfoAutoMatched(_nfoFileName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: scheme.tertiary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _backendRow(AppLocalizations l10n, ColorScheme scheme) {
    final profiles = context.watch<AiProfilesService>().services;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 230,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(l10n.scrapeBackend),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _backend?.id,
                isExpanded: true,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                decoration: InputDecoration(
                  helperText: profiles.isEmpty ? l10n.scrapeBackendNone : null,
                ),
                items: [
                  for (final s in profiles)
                    DropdownMenuItem(
                      value: s.id,
                      child: Row(
                        children: [
                          _BackendAvatar(name: s.name),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (s.toAiConfig().isComplete) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.tertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                onChanged: profiles.isEmpty
                    ? null
                    : (v) => setState(() => _backendId = v),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(l10n.scrapeCustomPrompt),
              const SizedBox(height: 8),
              TextField(
                controller: _instructions,
                decoration: InputDecoration(
                  hintText: l10n.scrapeCustomPromptHint,
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cookies and the HTML paste fallback: both are escape hatches, and putting
  /// them behind a disclosure keeps the common path to three fields.
  Widget _advanced(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    return Container(
      decoration: BoxDecoration(
        color: glass.panelFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glass.panelStroke),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(
                children: [
                  Text(
                    l10n.scrapeAdvanced,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvanced)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _cookies,
                    decoration: InputDecoration(
                      hintText: l10n.scrapeCookiesLabel,
                      helperText: l10n.scrapeCookiesHint,
                      prefixIcon: const Icon(Icons.cookie_outlined, size: 16),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!_showPaste)
                    TextButton.icon(
                      onPressed: () => setState(() => _showPaste = true),
                      icon: const Icon(Icons.content_paste_rounded, size: 15),
                      label: Text(l10n.scrapePasteHtml),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(fontSize: 12.5),
                      ),
                    )
                  else
                    TextField(
                      controller: _html,
                      maxLines: 5,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.scrapePasteHtml,
                        helperText: l10n.scrapePasteHtmlHint,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(AppLocalizations l10n, ColorScheme scheme) {
    final working = _stage == _Stage.working;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
      child: Row(
        children: [
          if (working)
            _ElapsedLabel(elapsed: _elapsed, format: _format)
          else if (_provider() != null)
            OutlinedButton.icon(
              onPressed: () => _run(askLlm: true),
              icon: const Icon(Icons.auto_awesome_outlined, size: 15),
              label: Text(l10n.scrapeAskLlm),
            ),
          const Spacer(),
          TextButton(
            onPressed: () {
              if (working) {
                _cancel?.cancel();
              } else {
                Navigator.pop(context);
              }
            },
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: working ? null : () => _run(askLlm: false),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(working ? l10n.scrapeWorking : l10n.scrapeProcess),
          ),
        ],
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Small pieces ────────────────────────────────────────────────────────────

class _ElapsedLabel extends StatefulWidget {
  final Stopwatch elapsed;
  final String Function(Duration) format;
  const _ElapsedLabel({required this.elapsed, required this.format});

  @override
  State<_ElapsedLabel> createState() => _ElapsedLabelState();
}

class _ElapsedLabelState extends State<_ElapsedLabel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Text(
      l10n.scrapeElapsed(widget.format(widget.elapsed.elapsed)),
      style: TextStyle(
        fontSize: 11.5,
        fontFamily: 'monospace',
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// The design's small section captions — quieter than a field label, so the
/// values carry the visual weight.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// Two-letter monogram for an AI profile, standing in for a provider logo.
class _BackendAvatar extends StatelessWidget {
  final String name;
  const _BackendAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, name.trim().length >= 2 ? 2 : 1);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

enum _StepState { done, active, pending }

/// One row of the working card: ✓ done, ● active, ○ pending.
class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;

  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (state) {
      _StepState.done => (Icons.check_rounded, scheme.tertiary),
      _StepState.active => (Icons.circle, scheme.primary),
      _StepState.pending => (
        Icons.circle_outlined,
        scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    };

    return Opacity(
      opacity: state == _StepState.pending ? 0.5 : 1,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Icon(
              icon,
              size: state == _StepState.active ? 9 : 15,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: state == _StepState.active
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
          if (state == _StepState.active) ...[
            const Spacer(),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
