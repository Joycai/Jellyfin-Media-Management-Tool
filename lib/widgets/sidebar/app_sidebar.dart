import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_service.dart';
import '../../services/file_browser_service.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';

/// 侧边栏（2.6 / 3.1）。
///
/// 宽 244，可拖拽 200–360；行高 32、圆角 8、内距 `7 / 10`；分组标题
/// 10px · 600 · 0.08em；底部固定 AI 状态卡。
///
/// **< 1180 折叠成 64 图标栏。** 折叠不是把文字省略掉 —— 那样每一行都变成一个
/// 猜谜；折叠后只留图标，标签移进 tooltip。
class AppSidebar extends StatefulWidget {
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  const AppSidebar({super.key, this.collapsed = false, this.onToggleCollapsed});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  /// 折叠态里保留几条「最近」。
  static const _collapsedRecents = 4;

  /// 用户拖出来的宽度；null = 用设计稿的 244。
  double? _width;

  /// 拖动中的实时宽度。
  ///
  /// 和列宽拖拽是同一个道理：写进 `SettingsService` 会在每个指针事件上通知全应用
  /// 的监听者，并重新武装 `config.json` 的保存去抖 —— 每一个像素一次。
  double? _dragWidth;

  /// Home plus whatever the mount scan has found so far.
  ///
  /// Home comes out of the environment, which is already in memory, so it is
  /// there on the first frame. The volumes need a directory scan, and that is
  /// the part that used to happen inside `build`: on the UI isolate, and again
  /// on *every* sidebar rebuild -- which is every file-list reload and every
  /// selection change, because the sidebar watches both services. On macOS
  /// `/Volumes` holds an entry per mounted volume and a NAS that has gone to
  /// sleep can take seconds to answer for one of them, which was a stalled
  /// frame each time.
  List<_Location> _locations = _initialLocations();

  static List<_Location> _initialLocations() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return const [];
    return [_Location(Icons.home_rounded, 'Home', home)];
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadVolumes());
  }

  /// Appends the mounted volumes once the scan finishes.
  ///
  /// Returns before any `await` on platforms with no mount root to scan, so
  /// `setState` is never reached during `initState` -- calling it there is a
  /// framework error, not a no-op.
  Future<void> _loadVolumes() async {
    final String? root;
    if (Platform.isMacOS) {
      root = '/Volumes';
    } else if (Platform.isLinux) {
      root = '/mnt';
    } else {
      root = null;
    }
    if (root == null) return;

    final volumes = <_Location>[];
    try {
      final dir = Directory(root);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory) {
            volumes.add(
              _Location(
                Icons.storage_rounded,
                p.basename(entity.path),
                entity.path,
              ),
            );
          }
        }
      }
    } catch (_) {
      // An unreadable mount root means fewer shortcuts, not a broken sidebar;
      // there is nothing the user could do about it from here.
    }

    if (!mounted || volumes.isEmpty) return;
    setState(() => _locations = [..._locations, ...volumes]);
  }

  void _open(String path) {
    context.read<FileBrowserService>().setCurrentDirectory(path);
    context.read<SettingsService>().pushRecent(path);
  }

  static String _label(String path) =>
      p.basename(path).isEmpty ? path : p.basename(path);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = widget.collapsed
        ? AppSizes.sidebarCollapsed
        : (_dragWidth ?? _width ?? AppSizes.sidebar);

    // 抓取边压在栏内、不额外占宽：侧栏的 244 是**含**这条边的总宽，否则父级
    // 分配 244 时 Row 会溢出 4px。
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppGlassPane(
              border: Border(right: BorderSide(color: t.stroke)),
              child: widget.collapsed
                  ? _collapsed(context)
                  : _expanded(context),
            ),
          ),
          if (!widget.collapsed)
            Positioned(top: 0, bottom: 0, right: 0, child: _resizeHandle()),
        ],
      ),
    );
  }

  Widget _resizeHandle() => MouseRegion(
    cursor: SystemMouseCursors.resizeLeftRight,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) =>
          setState(() => _dragWidth = _width ?? AppSizes.sidebar),
      onHorizontalDragUpdate: (d) => setState(() {
        _dragWidth = ((_dragWidth ?? AppSizes.sidebar) + d.delta.dx).clamp(
          AppSizes.sidebarMin,
          AppSizes.sidebarMax,
        );
      }),
      // 取消也提交：列已经在屏幕上移动过了，丢掉待定宽度会让它在指针底下弹回去。
      onHorizontalDragEnd: (_) => _commitDrag(),
      onHorizontalDragCancel: _commitDrag,
      child: const SizedBox(width: 4),
    ),
  );

  void _commitDrag() => setState(() {
    _width = _dragWidth ?? _width;
    _dragWidth = null;
  });

  Widget _expanded(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final browser = context.watch<FileBrowserService>();
    final current = browser.currentDirectory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md12,
              AppSpacing.lg,
              AppSpacing.md12,
              AppSpacing.md12,
            ),
            children: [
              AppGroupLabel(l10n.favorites),
              if (settings.favorites.isEmpty)
                _EmptyHint(l10n.noFavorites)
              else
                ...settings.favorites.map(
                  (path) => _NavTile(
                    icon: Icons.star_rounded,
                    label: _label(path),
                    tooltip: path,
                    selected: path == current,
                    onTap: () => _open(path),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              AppGroupLabel(l10n.recent),
              if (settings.recent.isEmpty)
                _EmptyHint(l10n.noRecent)
              else
                ...settings.recent.map(
                  (path) => _NavTile(
                    icon: Icons.history_rounded,
                    label: _label(path),
                    tooltip: path,
                    selected: path == current,
                    onTap: () => _open(path),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              AppGroupLabel(l10n.locations),
              ..._locations.map(
                (loc) => _NavTile(
                  icon: loc.icon,
                  label: loc.label,
                  tooltip: loc.path,
                  selected: loc.path == current,
                  onTap: () => _open(loc.path),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md12,
            0,
            AppSpacing.md12,
            AppSpacing.md12,
          ),
          child: _AiStatusCard(),
        ),
      ],
    );
  }

  /// 64 图标栏：每组只留一枚代表图标，标签进 tooltip。
  Widget _collapsed(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final browser = context.watch<FileBrowserService>();
    final current = browser.currentDirectory;
    final t = context.tokens;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            children: [
              for (final path in settings.favorites)
                _CollapsedTile(
                  icon: Icons.star_rounded,
                  tooltip: '${l10n.favorites} · ${_label(path)}',
                  selected: path == current,
                  onTap: () => _open(path),
                ),
              if (settings.favorites.isNotEmpty && settings.recent.isNotEmpty)
                const _RailDivider(),
              // 最近访问在折叠态里全是同一个时钟字形 —— 八行一模一样的图标既认不
              // 出来也点不准，所以只留最近的几条，其余等展开再说。
              for (final path in settings.recent.take(_collapsedRecents))
                _CollapsedTile(
                  icon: Icons.history_rounded,
                  tooltip: '${l10n.recent} · ${_label(path)}',
                  selected: path == current,
                  onTap: () => _open(path),
                ),
              if (_locations.isNotEmpty) const _RailDivider(),
              for (final loc in _locations)
                _CollapsedTile(
                  icon: loc.icon,
                  tooltip: loc.label,
                  selected: loc.path == current,
                  onTap: () => _open(loc.path),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md12),
          child: Consumer<AiService>(
            builder: (context, ai, _) => Tooltip(
              message: ai.isConfigured ? ai.config.model : l10n.aiNotConfigured,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor(ai, t),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Color _statusColor(AiService ai, AppTokens t) => switch (ai.status) {
  ConnectionStatus.connected => t.success,
  ConnectionStatus.error => t.danger,
  ConnectionStatus.testing => t.warning,
  ConnectionStatus.unknown => t.textMuted,
};

class _Location {
  final IconData icon;
  final String label;
  final String path;
  const _Location(this.icon, this.label, this.path);
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.xxs,
    ),
    child: Text(
      text,
      style: AppTypeScale.caption.copyWith(color: context.tokens.textMuted),
    ),
  );
}

/// 侧栏行：高 32、圆角 8、内距 `7 / 10`、gap 10。
class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  // 设计稿的行尾计数（「电影 238」）在这里刻意没有做：按目录数条目要么每次进
  // 侧栏都去 stat 整棵树，要么维护一份会过期的缓存，两者都比这个数字值钱。
  // 见 docs/spec/ui-redesign/backlog.md。

  const _NavTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: AppMotion.progress,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: AppMotion.respecting(context, AppMotion.hover),
              curve: AppMotion.standard,
              height: AppSizes.sidebarRowHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: widget.selected
                    ? t.selectionFill
                    : _hover
                    ? t.controlFill
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.button),
                border: widget.selected
                    ? Border.all(color: t.selectionStroke)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 14,
                    color: widget.selected
                        ? t.textTitle
                        : t.textSecondary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypeScale.body.copyWith(
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.selected ? t.textTitle : t.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 折叠栏里的分组分隔线 —— 没有分组标题可写，只能靠一条线。
class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Divider(height: 1, thickness: 1, color: context.tokens.stroke),
  );
}

class _CollapsedTile extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _CollapsedTile({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: AppIconButton(
      icon: icon,
      tooltip: tooltip,
      active: selected,
      onPressed: onTap,
    ),
  );
}

/// 底部固定的 AI 状态卡（3.1）。
class _AiStatusCard extends StatelessWidget {
  const _AiStatusCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ai = context.watch<AiService>();
    final t = context.tokens;

    final dot = _statusColor(ai, t);
    final title = switch (ai.status) {
      ConnectionStatus.connected => l10n.aiConnected,
      ConnectionStatus.error => l10n.aiConnectionError,
      ConnectionStatus.testing => l10n.aiTesting,
      ConnectionStatus.unknown =>
        ai.isConfigured ? l10n.aiReady : l10n.aiNotConfigured,
    };

    return AppCard(
      radius: AppRadii.panel,
      padding: const EdgeInsets.all(AppSpacing.md12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  // 已连接时给圆点一圈同色辉光 —— 设计稿只在这一处用发光，
                  // 因为「服务活着」是侧栏里唯一需要余光就能看到的状态。
                  boxShadow:
                      ai.status == ConnectionStatus.connected &&
                          !t.reduceEffects
                      ? [
                          BoxShadow(
                            color: dot.withValues(alpha: 0.8),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.caption.copyWith(
                    fontWeight: FontWeight.w500,
                    color: t.textBody,
                  ),
                ),
              ),
            ],
          ),
          if (ai.isConfigured) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              ai.config.model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.monoSmall.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.itemsProcessed(ai.itemsProcessed),
              style: AppTypeScale.monoTiny.copyWith(color: t.textDisabled),
            ),
          ],
        ],
      ),
    );
  }
}
