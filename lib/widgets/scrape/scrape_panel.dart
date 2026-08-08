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
}) => showDialog<ScrapePanelResult>(
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

class _ScrapePanelState extends State<ScrapePanel> {
  final _url = TextEditingController();
  final _html = TextEditingController();
  final _cookies = TextEditingController();
  final _instructions = TextEditingController();

  late String _targetDir = widget.targetDir;
  late String _nfoFileName = widget.nfoFileName;

  /// True once the user picked the NFO themselves, so the caption stops
  /// claiming it was auto-detected.
  bool _nfoChosen = false;

  String? _backendId;
  bool _showPaste = false;
  bool _showAdvanced = false;

  _Stage _stage = _Stage.setup;
  String? _error;
  AiCancelToken? _cancel;

  /// Set while a direct extraction is running, so the progress line can say
  /// which of the two buttons is being honoured.
  bool _askingLlm = false;

  ScrapeResult? _result;
  ScrapeImageCache? _cache;

  /// Images still to fetch for the grid. Drives the header's progress line.
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
      setState(() => _error = l10n.scrapeUrlInvalid);
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

    setState(() {
      _stage = _Stage.working;
      _askingLlm = askLlm;
      _error = null;
      _cancel = token;
    });

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
            )
          : await scraper.scrapeHtml(
              pasted,
              sourceUrl: url.toString(),
              targetDir: _targetDir,
              nfoFileName: _nfoFileName,
              learner: askLlm ? null : learner,
            );

      if (askLlm) {
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
      token.dispose();
      if (mounted) _cancel = null;
    }
  }

  /// Opens a search for the detected code in the browser.
  ///
  /// Knowing the catalogue number is not the same as knowing the URL, and the
  /// panel cannot ask for one the user does not have yet. Uses the same site
  /// list they curate in Settings — there is no second table.
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

  Future<void> _search(SearchSite site, String keyword) async {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final reviewing = _stage == _Stage.results;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        // Setting a scrape up is a short form; reviewing one is a table beside
        // a picture grid. The window grows to match rather than making the
        // form sprawl or the review cramped.
        constraints: BoxConstraints(
          maxWidth: reviewing ? 1180 : 720,
          maxHeight: reviewing ? 800 : 760,
        ),
        child: reviewing
            ? _review()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(l10n, scheme),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      child: _stage == _Stage.working
                          ? _working(l10n, scheme)
                          : _setup(l10n, scheme),
                    ),
                  ),
                  const Divider(height: 1),
                  _footer(l10n, scheme),
                ],
              ),
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
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
    child: Row(
      children: [
        Icon(Icons.travel_explore_outlined, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.scrapePanelTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _working(AppLocalizations l10n, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        const SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 18),
        Text(
          _askingLlm ? l10n.scrapeAskLlm : l10n.scrapeWorking,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(
          _url.text.trim(),
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
  );

  Widget _setup(AppLocalizations l10n, ColorScheme scheme) {
    final glass = Theme.of(context).extension<GlassTheme>()!;
    final profiles = context.watch<AiProfilesService>().services;
    final sites = context.watch<SettingsService>().searchSites;
    final keyword = widget.suggestedKeyword;
    final recipe = _parsedUrl() == null
        ? null
        : context.watch<RecipeStore>().forUrl(_parsedUrl()!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _url,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.scrapeUrlLabel,
            hintText: 'https://…',
            prefixIcon: const Icon(Icons.link_rounded, size: 20),
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
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
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
        if (_url.text.trim().isEmpty &&
            keyword != null &&
            sites.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: glass.panelFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glass.panelStroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.scrapeDetectedCode(keyword),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final site in sites)
                      OutlinedButton.icon(
                        onPressed: () => _search(site, keyword),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: Text(site.name),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: scheme.primary,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Where it lands. Auto-detected from what was right-clicked, because
        // that is right almost every time, but never a dead end.
        Text(
          l10n.scrapeNfoTarget,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: glass.panelFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: glass.panelStroke),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.join(_targetDir, _nfoFileName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (!_nfoChosen) ...[
                      const SizedBox(height: 2),
                      Text(
                        l10n.scrapeNfoAutoDetected(widget.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _browseForNfo,
                child: Text(l10n.scrapeNfoBrowse),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          initialValue: _backend?.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.scrapeBackend,
            prefixIcon: const Icon(Icons.smart_toy_outlined, size: 20),
            border: const OutlineInputBorder(),
            helperText: profiles.isEmpty ? l10n.scrapeBackendNone : null,
          ),
          items: [
            for (final s in profiles)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: profiles.isEmpty
              ? null
              : (v) => setState(() => _backendId = v),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _instructions,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l10n.scrapeCustomPrompt,
            hintText: l10n.scrapeCustomPromptHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.scrapeAskLlmHint,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 8),
        _advanced(l10n, scheme),
      ],
    );
  }

  /// Cookies and the HTML paste fallback: both are escape hatches, and putting
  /// them behind a disclosure keeps the common path to three fields.
  Widget _advanced(AppLocalizations l10n, ColorScheme scheme) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: _showAdvanced,
      onExpansionChanged: (v) => _showAdvanced = v,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(
        l10n.scrapeAdvanced,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      children: [
        TextField(
          controller: _cookies,
          decoration: InputDecoration(
            labelText: l10n.scrapeCookiesLabel,
            hintText: l10n.scrapeCookiesHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (!_showPaste)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showPaste = true),
              icon: const Icon(Icons.content_paste_rounded, size: 17),
              label: Text(l10n.scrapePasteHtml),
            ),
          )
        else
          TextField(
            controller: _html,
            maxLines: 5,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: l10n.scrapePasteHtml,
              helperText: l10n.scrapePasteHtmlHint,
              border: const OutlineInputBorder(),
            ),
          ),
      ],
    ),
  );

  Widget _footer(AppLocalizations l10n, ColorScheme scheme) {
    final working = _stage == _Stage.working;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        children: [
          if (!working && _provider() != null)
            OutlinedButton.icon(
              onPressed: () => _run(askLlm: true),
              icon: const Icon(Icons.psychology_outlined, size: 18),
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
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: working ? null : () => _run(askLlm: false),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(l10n.scrapeProcess),
          ),
        ],
      ),
    );
  }
}
