import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/history_entry.dart';
import '../../services/history_service.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';
import 'organize_history_screen.dart';

/// 操作历史浮层（5.4）。
///
/// 宽 380、最大高 420、圆角 12（Windows 10），与顶栏间距 8，箭头对齐历史按钮
/// 中心。这是历史的**主形态** —— 撤销上一步是随手的动作，为它推一整页会让人
/// 先丢掉当前的上下文再找回来。「全部记录」才跳到独立窗口。
///
/// 点击浮层外、Esc、切换分区都关闭；关闭 120ms 向上 4px 淡出。
Future<void> showHistoryPopover(BuildContext context, {required Rect anchor}) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // 浮层不压暗背景：它锚在顶栏上，不是一个模态决定。
    barrierColor: Colors.transparent,
    transitionDuration: reduced ? Duration.zero : AppMotion.overlayIn,
    pageBuilder: (ctx, _, _) => _HistoryPopover(anchor: anchor),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standard,
        reverseCurve: AppMotion.standard,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _HistoryPopover extends StatefulWidget {
  final Rect anchor;
  const _HistoryPopover({required this.anchor});

  @override
  State<_HistoryPopover> createState() => _HistoryPopoverState();
}

class _HistoryPopoverState extends State<_HistoryPopover> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<HistoryService>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = AppLocalizations.of(context)!;
    final history = context.watch<HistoryService>();
    final screen = MediaQuery.sizeOf(context);

    // 箭头对齐按钮中心，面板右缘尽量贴着它，但不越出屏幕。
    const width = AppSizes.popoverWidth;
    final centre = widget.anchor.center.dx;
    var left = centre + widget.anchor.width / 2 - width;
    left = left.clamp(AppSpacing.sm, screen.width - width - AppSpacing.sm);
    final arrowDx = centre - left - 5.5;
    final top = widget.anchor.bottom + AppSpacing.sm;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: AppSizes.popoverMaxHeight,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GlassSurface(
                  fill: Theme.of(context).colorScheme.surface.withValues(
                    alpha: t.isDark ? 0.92 : 0.97,
                  ),
                  blur: t.blurPanel,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: t.strokeStrong),
                  shadow: t.elevation.overlay,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context, l10n, history),
                      Flexible(
                        child: history.entries.isEmpty
                            ? _empty(context, l10n)
                            : _list(context, history),
                      ),
                      _footer(context, l10n),
                    ],
                  ),
                ),
                // 11×11 旋转 45° 的箭头，只画左上两条边，正好接上面板描边。
                Positioned(
                  top: -6,
                  left: arrowDx,
                  child: Transform.rotate(
                    angle: 0.7853981634,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          left: BorderSide(color: t.strokeStrong),
                          top: BorderSide(color: t.strokeStrong),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    HistoryService history,
  ) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        14,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.stroke)),
      ),
      child: Row(
        children: [
          Text(
            l10n.historyTitle,
            style: AppTypeScale.bodyStrong.copyWith(color: t.textTitle),
          ),
          const SizedBox(width: AppSizes.logoGap),
          if (history.entries.isNotEmpty)
            ShortcutPill('${history.entries.length}'),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                OrganizeHistoryScreen.show(context);
              },
              child: Text(
                l10n.historyAllRecords,
                style: AppTypeScale.caption.copyWith(color: t.accentText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations l10n) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Text(
          l10n.historyEmpty,
          style: AppTypeScale.caption.copyWith(color: t.textMuted),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, HistoryService history) {
    final l10n = AppLocalizations.of(context)!;
    // 按天分组：设计稿的浮层用「今天 / 昨天 / 日期」做分组标题，因为撤销的
    // 心智单位是「我刚才做的」，不是第几条。
    final groups = <String, List<HistoryEntry>>{};
    for (final e in history.entries) {
      groups.putIfAbsent(_dayLabel(l10n, e.createdAt), () => []).add(e);
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.xs),
      children: [
        for (final entry in groups.entries) ...[
          AppGroupLabel(
            entry.key,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xxs + 1,
            ),
          ),
          for (final e in entry.value) _PopoverRow(entry: e),
        ],
      ],
    );
  }

  int get _count => context.read<HistoryService>().entries.length;

  Widget _footer(BuildContext context, AppLocalizations l10n) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.stroke)),
      ),
      child: Row(
        children: [
          Text(
            l10n.historyRetention(HistoryService.retentionDays),
            style: AppTypeScale.caption.copyWith(color: t.textMuted),
          ),
          const Spacer(),
          // 设计稿这里写的是「⌘Z 撤销上一步」。应用没有那个快捷键，写上去就是
          // 教用户按一个没有反应的键 —— 改成陈述条数，快捷键本身进 backlog。
          Text(
            l10n.itemsCount(_count),
            style: AppTypeScale.monoTiny.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }

  static String _dayLabel(AppLocalizations l10n, DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return l10n.historyToday;
    if (diff == 1) return l10n.timeYesterday;
    return '${t.year}-${_two(t.month)}-${_two(t.day)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// 浮层里的一行：高 44、圆角 9、gap 11（5.4）。
class _PopoverRow extends StatefulWidget {
  final HistoryEntry entry;
  const _PopoverRow({required this.entry});

  @override
  State<_PopoverRow> createState() => _PopoverRowState();
}

class _PopoverRowState extends State<_PopoverRow> {
  bool _hover = false;
  bool _busy = false;

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final history = context.read<HistoryService>();
    setState(() => _busy = true);
    final result = await history.undo(widget.entry);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.hasFailures
              ? l10n.undoPartial(result.failures.length, result.succeeded)
              : l10n.undoDone(result.succeeded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = AppLocalizations.of(context)!;
    final e = widget.entry;
    final (icon, tint) = _kindStyle(e.kind, t);

    // 不可撤销的项整行 55% 不透明，副文案直接写「不可撤销」，
    // 不用禁用态按钮占位 —— 一个灰按钮只是在邀请人去点它。
    final row = Container(
      height: AppSizes.rowTall,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: _hover && e.canUndo ? t.controlFill : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.icon),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.logo,
            height: AppSizes.logo,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 13, color: t.textBody),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(l10n, e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.control.copyWith(
                    fontWeight: FontWeight.w500,
                    color: t.textTitle,
                  ),
                ),
                Text(
                  e.canUndo
                      ? '${_time(e.createdAt)} · ${p.basename(e.baseDir)}'
                      : '${_time(e.createdAt)} · ${l10n.historyIrreversible}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.monoSmall.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          // 撤销按钮**只在可撤销且悬停时**出现。
          if (e.canUndo && (_hover || _busy)) ...[
            const SizedBox(width: AppSpacing.sm),
            _busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  )
                : AppButton(
                    label: l10n.undoAction,
                    height: AppSizes.controlXs,
                    onPressed: _undo,
                  ),
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(
        opacity: e.canUndo ? 1 : AppTokens.inertRowOpacity,
        child: row,
      ),
    );
  }

  static (IconData, Color) _kindStyle(HistoryKind kind, AppTokens t) =>
      switch (kind) {
        HistoryKind.manualRename => (
          Icons.edit_outlined,
          t.accent.withValues(alpha: 0.20),
        ),
        HistoryKind.metadataRefresh => (
          Icons.download_outlined,
          t.success.withValues(alpha: 0.18),
        ),
        HistoryKind.aiOrganize => (
          Icons.auto_awesome,
          t.ai.withValues(alpha: 0.20),
        ),
        HistoryKind.batchImport => (
          Icons.arrow_forward_rounded,
          t.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : AppPalette.ink.withValues(alpha: 0.07),
        ),
      };

  static String _title(AppLocalizations l10n, HistoryEntry e) =>
      switch (e.kind) {
        HistoryKind.aiOrganize => l10n.historyTitleAi(e.itemCount),
        HistoryKind.manualRename => l10n.historyTitleManual(e.itemCount),
        HistoryKind.metadataRefresh => l10n.historyTitleMetadata,
        HistoryKind.batchImport => l10n.historyTitleImport(e.itemCount),
      };

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
