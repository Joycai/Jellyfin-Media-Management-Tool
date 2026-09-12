import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scrape_recipe.dart';
import '../../services/scrape/cookie_store.dart';
import '../../services/scrape/recipe_store.dart';
import '../../services/scrape/scrape_service.dart';
import '../../theme/design_tokens.dart';
import 'settings_controls.dart';

/// Cookie management and the recipe list.
///
/// Stateful because `CookieStore` is a plain in-memory object rather than a
/// `ChangeNotifier` — deliberately, so no listener can leak a session cookie
/// into a rebuild somewhere else. This screen owns the only view of it and
/// refreshes itself after each mutation.
// ── Scraping section ────────────────────────────────────────────────────────

class ScrapingSection extends StatefulWidget {
  const ScrapingSection({super.key});

  @override
  State<ScrapingSection> createState() => _ScrapingSectionState();
}

class _ScrapingSectionState extends State<ScrapingSection> {
  CookieStore get _cookies => context.read<ScrapeService>().fetcher.cookies;

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final store = _cookies;

    final picked = await FilePicker.pickFile(
      dialogTitle: l10n.settingsScrapeImportCookies,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    final path = picked?.path;
    if (path == null) return;

    List<NetscapeCookie> parsed;
    try {
      parsed = CookieStore.parseNetscape(await File(path).readAsString());
    } catch (_) {
      parsed = const [];
    }
    if (parsed.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsScrapeCookieImportFailed)),
      );
      return;
    }
    store.importAll(parsed);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsScrapeCookieImported(parsed.length))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final store = _cookies;

    // Grouped by host: one row per site is what the user reasons about, not
    // one row per cookie.
    final byDomain = <String, List<NetscapeCookie>>{};
    for (final c in store.cookies) {
      byDomain.putIfAbsent(c.domain, () => []).add(c);
    }
    final domains = byDomain.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        SettingsSectionTitle(l10n.settingsScrapeCookies),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.settingsScrapeCookieWarning,
                      style: TextStyle(
                        fontSize: AppTypeScale.sizeControl,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _import,
                    icon: const Icon(Icons.upload_file_outlined, size: 17),
                    label: Text(l10n.settingsScrapeImportCookies),
                  ),
                  const SizedBox(width: 10),
                  if (domains.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(store.clear),
                      child: Text(l10n.settingsScrapeClearCookies),
                    ),
                ],
              ),
              if (domains.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.settingsScrapeCookieEmpty,
                  style: TextStyle(
                    fontSize: AppTypeScale.sizeBody,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              for (final domain in domains) ...[
                SettingsDivider(),
                _CookieDomainRow(
                  domain: domain,
                  cookies: byDomain[domain]!,
                  onClear: () => setState(() => store.clearDomain(domain)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 26),
        SettingsSectionTitle(l10n.settingsScrapeRecipes),
        const _RecipeList(),
      ],
    );
  }
}

/// One host's cookies. Names only — a value is the credential, and there is no
/// reason to ever put one on screen.
class _CookieDomainRow extends StatelessWidget {
  final String domain;
  final List<NetscapeCookie> cookies;
  final VoidCallback onClear;

  const _CookieDomainRow({
    required this.domain,
    required this.cookies,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                domain,
                style: const TextStyle(
                  fontSize: AppTypeScale.sizeBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              l10n.settingsScrapeCookieCount(cookies.length),
              style: TextStyle(
                fontSize: AppTypeScale.sizeCaption,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onClear,
              child: Text(l10n.settingsScrapeClearDomain),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final c in cookies)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadii.tiny),
                ),
                child: Text(
                  '${c.name}=••••',
                  style: TextStyle(
                    fontSize: AppTypeScale.sizeCaption,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Read-only view of every recipe, learned ones first. Built-ins cannot be
/// deleted — they ship in code, so "deleting" one would only last until the
/// next launch.
class _RecipeList extends StatelessWidget {
  const _RecipeList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<RecipeStore>();
    final recipes = store.all;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < recipes.length; i++) ...[
            if (i > 0) SettingsDivider(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipes[i].domain,
                        style: const TextStyle(
                          fontSize: AppTypeScale.sizeBody,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recipes[i].pathPattern.isEmpty
                            ? l10n.settingsScrapeRecipeAnyPath
                            : recipes[i].pathPattern,
                        style: TextStyle(
                          fontSize: AppTypeScale.sizeCaption,
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  l10n.settingsScrapeRecipeHealth(
                    recipes[i].successCount,
                    recipes[i].failCount,
                  ),
                  style: TextStyle(
                    fontSize: AppTypeScale.sizeCaption,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                _RecipeBadge(recipe: recipes[i]),
                if (recipes[i].origin != RecipeOrigin.builtin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: l10n.settingsScrapeRecipeDelete,
                    onPressed: () => store.remove(recipes[i]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecipeBadge extends StatelessWidget {
  final ScrapeRecipe recipe;
  const _RecipeBadge({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Retirement is the interesting state, so it wins over the origin label.
    final (label, color) = recipe.isRetired
        ? (l10n.settingsScrapeRecipeRetired, scheme.error)
        : switch (recipe.origin) {
            RecipeOrigin.builtin => (
              l10n.settingsScrapeRecipeBuiltin,
              scheme.onSurfaceVariant,
            ),
            RecipeOrigin.llm => (
              l10n.settingsScrapeRecipeLearned,
              AppPalette.warning,
            ),
            RecipeOrigin.user => (
              l10n.settingsScrapeRecipeUser,
              scheme.primary,
            ),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.tiny),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypeScale.sizeMono,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
