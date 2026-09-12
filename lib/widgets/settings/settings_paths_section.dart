import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import 'settings_controls.dart';

/// 6.2 · 路径与位置（设计稿画板 21）。
///
/// 左列讲「库在哪」，右列讲「你常去哪」。设计稿的左列几乎整块是应用还没有的能力
/// —— 多根目录、挂载状态、重新扫描、独立的输出与临时目录 —— 所以那两张卡按设计
/// 稿的版式画出来后整体压暗并标注，而不是把右列的收藏 / 最近撑满整页假装页面很
/// 完整。收藏与最近是真的，读的就是 [SettingsService] 里那两份列表。
class PathsSection extends StatelessWidget {
  const PathsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsPage(
      children: [
        SettingsColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionTitle(
                l10n.pathsLibraryRoots,
                trailing: SettingsSoonTag(l10n.comingSoon),
              ),
              const _LibraryRootsPlaceholder(),
              const SizedBox(height: AppSpacing.xl),
              SettingsSectionTitle(
                l10n.pathsDefaults,
                trailing: SettingsSoonTag(l10n.comingSoon),
              ),
              const _DefaultLocationsPlaceholder(),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionTitle(l10n.pathsFavorites),
              const _FavoritePaths(),
              SettingsFootnote(l10n.pathsFavoritesHint),
              const SizedBox(height: AppSpacing.xl),
              SettingsSectionTitle(
                l10n.pathsRecent,
                trailing: SettingsPlaceholder(
                  child: SettingsMiniButton(l10n.pathsClearRecent),
                ),
              ),
              const _RecentPaths(),
              SettingsFootnote(l10n.pathsRecentHint(SettingsService.maxRecent)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 左列：还没有的能力，按设计稿画成占位 ──────────────────────────────────

class _LibraryRootsPlaceholder extends StatelessWidget {
  const _LibraryRootsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return SettingsPlaceholder(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRowsCard(
            children: [
              SettingsRow(
                leading: const SettingsRowIcon(Icons.movie_outlined),
                title: l10n.pathsRootMovies,
                subtitle: l10n.pathsRootExample,
                trailing: [
                  AppTag(label: l10n.pathsMounted, color: t.success),
                  SettingsMiniButton(l10n.pathsChange),
                ],
              ),
              SettingsRow(
                leading: const SettingsRowIcon(Icons.live_tv_outlined),
                title: l10n.pathsRootShows,
                subtitle: l10n.pathsRootExampleShows,
                trailing: [
                  AppTag(label: l10n.pathsUnmounted, color: t.warning),
                  SettingsMiniButton(l10n.pathsChange),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              SettingsMiniButton(
                l10n.pathsAddRoot,
                icon: Icons.add,
                accent: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              SettingsMiniButton(l10n.pathsRescan),
            ],
          ),
          SettingsFootnote(l10n.pathsRootsPlaceholder),
        ],
      ),
    );
  }
}

class _DefaultLocationsPlaceholder extends StatelessWidget {
  const _DefaultLocationsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsPlaceholder(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRowsCard(
            children: [
              SettingsRow(
                title: l10n.pathsOrganizeOutput,
                subtitle: l10n.pathsOrganizeOutputValue,
                subtitleMono: false,
                trailing: [SettingsMiniButton(l10n.pathsChoose)],
              ),
              SettingsRow(
                title: l10n.pathsTempDir,
                subtitle: l10n.pathsTempDirValue,
                subtitleMono: false,
                trailing: [SettingsMiniButton(l10n.pathsChange)],
              ),
            ],
          ),
          SettingsFootnote(l10n.pathsDefaultsPlaceholder),
        ],
      ),
    );
  }
}

// ── 右列：真的 ─────────────────────────────────────────────────────────────

class _FavoritePaths extends StatelessWidget {
  const _FavoritePaths();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final favorites = context.select<SettingsService, List<String>>(
      (s) => s.favorites,
    );
    if (favorites.isEmpty) return _EmptyCard(l10n.noFavorites);
    return SettingsRowsCard(
      children: [
        for (final path in favorites)
          SettingsRow(
            leading: Icon(Icons.star_rounded, size: 14, color: t.warning),
            title: p.basename(path).isEmpty ? path : p.basename(path),
            subtitle: path,
            trailing: [
              // 设计稿的 ⋮⋮ 拖拽手柄：排序还没实现，所以画出来但抓不住。
              SettingsPlaceholder(
                child: Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: t.textDisabled,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _RecentPaths extends StatelessWidget {
  const _RecentPaths();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final recent = settings.recent;
    if (recent.isEmpty) return _EmptyCard(l10n.noRecent);
    return SettingsRowsCard(
      children: [
        for (final path in recent)
          SettingsRow(
            title: p.basename(path).isEmpty ? path : p.basename(path),
            subtitle: path,
            trailing: [
              // 行尾的 ☆：这是侧边栏早就有的「加入收藏」，不是新能力。
              AppIconButton(
                icon: settings.favorites.contains(path)
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                tooltip: l10n.pathsAddFavorite,
                size: AppSizes.controlXs,
                active: settings.favorites.contains(path),
                onPressed: () => settings.toggleFavorite(path),
              ),
            ],
          ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String label;
  const _EmptyCard(this.label);

  @override
  Widget build(BuildContext context) => SettingsCard(
    child: Text(
      label,
      style: AppTypeScale.control.copyWith(color: context.tokens.textMuted),
    ),
  );
}
