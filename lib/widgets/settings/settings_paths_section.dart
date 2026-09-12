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
/// 稿的版式画出来，行本身压暗并标注，而不是把右列的收藏 / 最近撑满整页假装页面
/// 很完整。收藏与最近是真的，读的就是 [SettingsService] 里那两份列表。
class PathsSection extends StatelessWidget {
  const PathsSection({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage(
    children: [
      // 画板 21 是一张 2×2 的 CSS grid，两列**共用行轨道**：同一行里两张卡上下
      // 沿都齐，两列的底部也齐。把每一列各摞成一竖排做不到这件事 —— 左列第一张
      // 卡长高，右列第一张卡不会跟着长，两列从第二张卡起就再也对不上。
      SettingsColumns(
        equalHeight: true,
        left: _LibraryRootsCard(),
        right: _FavoritePaths(),
      ),
      SizedBox(height: AppSpacing.lg),
      SettingsColumns(
        equalHeight: true,
        left: _DefaultLocationsCard(),
        right: _RecentPaths(),
      ),
    ],
  );
}

// ── 左列：还没有的能力，按设计稿画成占位 ──────────────────────────────────

/// 压暗的只有行与按钮，卡、标题和卡底那句说明照常显示 —— 说明存在的理由就是讲
/// 清楚这块为什么按不动，把它一起压暗是本末倒置。
class _LibraryRootsCard extends StatelessWidget {
  const _LibraryRootsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return SettingsRowsCard(
      header: SettingsCardHeader(
        l10n.pathsLibraryRoots,
        trailing: SettingsSoonTag(l10n.comingSoon),
      ),
      // 「＋ 添加根目录」那一排按钮在设计稿里不带上分割线，只留 10 的间距。
      footerDivider: false,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.md),
          SettingsPlaceholder(
            child: Row(
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
          ),
          SettingsFootnote(l10n.pathsRootsPlaceholder),
        ],
      ),
      children: [
        SettingsPlaceholder(
          child: SettingsRow(
            leading: const SettingsRowIcon(Icons.movie_outlined),
            title: l10n.pathsRootMovies,
            subtitle: l10n.pathsRootExample,
            trailing: [
              AppTag(label: l10n.pathsMounted, color: t.success),
              SettingsMiniButton(l10n.pathsChange),
            ],
          ),
        ),
        SettingsPlaceholder(
          child: SettingsRow(
            leading: const SettingsRowIcon(Icons.live_tv_outlined),
            title: l10n.pathsRootShows,
            subtitle: l10n.pathsRootExampleShows,
            trailing: [
              AppTag(label: l10n.pathsUnmounted, color: t.warning),
              SettingsMiniButton(l10n.pathsChange),
            ],
          ),
        ),
      ],
    );
  }
}

class _DefaultLocationsCard extends StatelessWidget {
  const _DefaultLocationsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsRowsCard(
      // 设计稿这一格用 `space-between` 把三行铺满行轨道 —— 那是在它自己那份
      // 「最近访问只有 4 条」的内容量下。应用的最近访问最多 8 条，这一行的轨道
      // 能有设计稿的两倍高，均分之后行与行相隔一百多像素，卡看上去是坏的而不是
      // 宽松的。所以这里只把说明钉在卡底，余量落在行与说明之间（见 backlog
      // C14）。22 的两张短卡内容是定长的，余量小且可预期，仍按设计稿铺开。
      footer: SettingsFootnote(l10n.pathsDefaultsPlaceholder),
      header: SettingsCardHeader(
        l10n.pathsDefaults,
        trailing: SettingsSoonTag(l10n.comingSoon),
      ),
      children: [
        SettingsPlaceholder(
          child: SettingsRow(
            title: l10n.pathsOrganizeOutput,
            subtitle: l10n.pathsOrganizeOutputValue,
            subtitleMono: false,
            trailing: [SettingsMiniButton(l10n.pathsChoose)],
          ),
        ),
        SettingsPlaceholder(
          child: SettingsRow(
            title: l10n.pathsTempDir,
            subtitle: l10n.pathsTempDirValue,
            subtitleMono: false,
            trailing: [SettingsMiniButton(l10n.pathsChange)],
          ),
        ),
        // 设计稿新加的一行。值是真的 —— NFO 与图片就写在媒体文件旁边；
        // 按不动的只是「更改」，见 backlog B24。
        SettingsPlaceholder(
          child: SettingsRow(
            title: l10n.pathsNfoOutput,
            subtitle: l10n.pathsNfoOutputValue,
            subtitleMono: false,
            trailing: [SettingsMiniButton(l10n.pathsChange)],
          ),
        ),
      ],
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
    return SettingsRowsCard(
      header: SettingsCardHeader(l10n.pathsFavorites),
      footer: SettingsFootnote(l10n.pathsFavoritesHint),
      children: [
        if (favorites.isEmpty)
          _EmptyRow(l10n.noFavorites)
        else
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
    return SettingsRowsCard(
      header: SettingsCardHeader(
        l10n.pathsRecent,
        // 设计稿把「清除记录」画成卡头上的一个文字链，不是一颗描边按钮。
        trailing: SettingsPlaceholder(
          child: AppButton.ghost(
            label: l10n.pathsClearRecent,
            height: AppSizes.controlXs,
          ),
        ),
      ),
      footer: SettingsFootnote(l10n.pathsRecentHint(SettingsService.maxRecent)),
      children: [
        if (recent.isEmpty)
          _EmptyRow(l10n.noRecent)
        else
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

/// 空列表也留在卡里：分组标题现在画在卡内，把卡换成别的东西就把标题一起换掉了。
class _EmptyRow extends StatelessWidget {
  final String label;
  const _EmptyRow(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(
      label,
      style: AppTypeScale.control.copyWith(color: context.tokens.textMuted),
    ),
  );
}
