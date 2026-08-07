import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/scrape/recipe_store.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

/// What the user asked for: a page to scrape, and optionally its HTML.
class ScrapeInput {
  final String url;

  /// Non-null when the user pasted the page source (tier 4). The URL is still
  /// required alongside it — relative links resolve against it.
  final String? pastedHtml;

  const ScrapeInput({required this.url, this.pastedHtml});
}

/// Asks where to scrape from.
///
/// [suggestedKeyword] is the catalogue code recovered from the file name; when
/// present the dialog offers one-click searches on the user's configured search
/// sites so they can find the product page without leaving the app.
Future<ScrapeInput?> showScrapeUrlDialog(
  BuildContext context, {
  required String targetLabel,
  String? suggestedKeyword,
}) => showDialog<ScrapeInput>(
  context: context,
  builder: (_) => _ScrapeUrlDialog(
    targetLabel: targetLabel,
    suggestedKeyword: suggestedKeyword,
  ),
);

class _ScrapeUrlDialog extends StatefulWidget {
  final String targetLabel;
  final String? suggestedKeyword;

  const _ScrapeUrlDialog({required this.targetLabel, this.suggestedKeyword});

  @override
  State<_ScrapeUrlDialog> createState() => _ScrapeUrlDialogState();
}

class _ScrapeUrlDialogState extends State<_ScrapeUrlDialog> {
  final _url = TextEditingController();
  final _html = TextEditingController();
  bool _pasteExpanded = false;
  bool _showUrlError = false;

  @override
  void dispose() {
    _url.dispose();
    _html.dispose();
    super.dispose();
  }

  /// Deliberately lenient: only the shape is checked here so the field can go
  /// green while typing. A host that refuses us, a 404 or a redirect loop are
  /// all left to `ScrapeService` to report properly.
  Uri? get _parsedUrl {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  void _submit() {
    final uri = _parsedUrl;
    if (uri == null) {
      setState(() => _showUrlError = true);
      return;
    }
    final html = _html.text.trim();
    Navigator.pop(
      context,
      ScrapeInput(
        url: uri.toString(),
        pastedHtml: html.isEmpty ? null : _html.text,
      ),
    );
  }

  Future<void> _search(SearchSite site, String keyword) async {
    final lang = Localizations.localeOf(context).languageCode;
    final url = site.url
        .replaceAll('{keyword}', Uri.encodeQueryComponent(keyword))
        .replaceAll('{lang}', lang);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final keyword = widget.suggestedKeyword;

    return AlertDialog(
      icon: Icon(Icons.travel_explore_outlined, color: scheme.primary),
      title: Text(l10n.scrapeUrlTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.scrapeUrlSubtitle(widget.targetLabel),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              if (keyword != null) ...[
                const SizedBox(height: 16),
                _CodeRow(keyword: keyword, onSearch: _search),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _url,
                autofocus: true,
                onChanged: (_) => setState(() => _showUrlError = false),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.scrapeUrlLabel,
                  hintText: l10n.scrapeUrlHint,
                  errorText: _showUrlError ? l10n.scrapeUrlInvalid : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              _CookieHint(url: _parsedUrl),
              const SizedBox(height: 6),
              Theme(
                // ExpansionTile draws its own divider lines that fight the
                // dialog's padding; the rest of the surface is unchanged.
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  initiallyExpanded: _pasteExpanded,
                  onExpansionChanged: (v) => setState(() => _pasteExpanded = v),
                  title: Text(
                    l10n.scrapePasteHtml,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  children: [
                    Text(
                      l10n.scrapePasteNeedsUrl,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _html,
                      minLines: 4,
                      maxLines: 8,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.scrapePasteHtmlHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.travel_explore_outlined, size: 18),
          label: Text(l10n.scrapeStart),
        ),
      ],
    );
  }
}

/// "Detected code: SPSF-43" plus a search button per configured site.
class _CodeRow extends StatelessWidget {
  final String keyword;
  final void Function(SearchSite, String) onSearch;

  const _CodeRow({required this.keyword, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;
    // The same list the user curates in settings — no second site table.
    final sites = context.watch<SettingsService>().searchSites;

    return Container(
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (sites.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final site in sites)
                  OutlinedButton.icon(
                    onPressed: () => onSearch(site, keyword),
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
        ],
      ),
    );
  }
}

/// Tells the user up front whether this host is one we already have an access
/// cookie for — the difference between "it just works" and "import a
/// cookies.txt when it fails".
class _CookieHint extends StatelessWidget {
  final Uri? url;
  const _CookieHint({required this.url});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final uri = url;
    if (uri == null) return const SizedBox.shrink();

    final recipe = context.watch<RecipeStore>().forUrl(uri);
    final builtIn = recipe?.cookies != null && recipe!.cookies!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          builtIn ? Icons.check_circle_outline : Icons.info_outline,
          size: 14,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            builtIn ? l10n.scrapeCookieBuiltIn : l10n.scrapeCookieMissing,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
