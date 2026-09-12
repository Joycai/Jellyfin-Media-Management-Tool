import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../ui/glass_surface.dart';

/// 对话框（1.4e）。
///
/// 圆角 12、描边、投影 L4，最大宽 **560**，超过内容自身滚动；标题 14/600，
/// 正文 12/1.7；底部操作条 white 3% + 顶部描边，内距 `12 18`，按钮右对齐，
/// **主操作永远在最右**。
///
/// Material 自己的 `Dialog` 画的是被 seed 色染过的 `surfaceContainerHigh`，
/// 一块和应用里其它任何东西都不搭的平板。这里换成近乎不透明的主题表面色 +
/// 背景模糊 —— 近乎不透明是刻意的：对话框的职责是被读，纯玻璃压在文件表格上
/// 会让文字游泳；剩下的约 8% 透明度才是它还叫玻璃的原因。
class GlassAlertDialog extends StatelessWidget {
  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// 卡片外宽上限。内容更窄时卡片跟着缩，和 [AlertDialog] 一样。
  final double maxWidth;

  const GlassAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.maxWidth = AppSizes.dialogMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl40,
        vertical: AppSpacing.xl24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GlassDialogSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  AppSpacing.lg,
                  18,
                  AppSpacing.md12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null || icon != null)
                      Row(
                        children: [
                          if (icon != null) ...[
                            icon!,
                            const SizedBox(width: AppSpacing.md12),
                          ],
                          if (title != null)
                            Expanded(
                              // merge, not replace: a plain DefaultTextStyle
                              // here would drop the ambient fontFamily (the
                              // user's UI font) along with everything else it
                              // doesn't set.
                              child: DefaultTextStyle.merge(
                                style: TextStyle(
                                  fontSize: AppTypeScale.sizeBody,
                                  fontWeight: FontWeight.w600,
                                  color: t.textTitle,
                                ),
                                child: title!,
                              ),
                            ),
                        ],
                      ),
                    if (content != null) ...[
                      if (title != null || icon != null)
                        const SizedBox(height: AppSpacing.xs),
                      Flexible(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: AppTypeScale.sizeCaption,
                            height: AppTypeScale.leadingBody,
                            color: t.textSecondary,
                          ),
                          child: content!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null && actions!.isNotEmpty)
                DialogActionBar(children: actions!),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部操作条：white 3% + 顶部 1px 描边，内距 `12 18`，右对齐。
///
/// 主操作永远在最右 —— 传进来的顺序就是从左到右的顺序。
class DialogActionBar extends StatelessWidget {
  final List<Widget> children;

  /// 左侧可放一个次要入口（设计稿 4.1 的「直接询问模型」）。
  final Widget? leading;

  const DialogActionBar({super.key, required this.children, this.leading});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: AppSpacing.md12,
      ),
      decoration: BoxDecoration(
        color: t.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : AppPalette.ink.withValues(alpha: 0.02),
        border: Border(top: BorderSide(color: t.stroke)),
      ),
      child: Row(
        children: [
          ?leading,
          const Spacer(),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

class GlassDialogSurface extends StatelessWidget {
  final Widget child;
  final double radius;

  const GlassDialogSurface({
    super.key,
    required this.child,
    this.radius = AppRadii.card,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scheme = Theme.of(context).colorScheme;

    // 已经近乎不透明，性能模式再走完剩下那一点几乎不损失什么：wash 变实色、
    // 滤镜跳过，而最贵的那层 60px 投影（画在比对话框还大的范围上）缩到仍然
    // 能把面抬起来的程度。
    final flat = t.reduceEffects;
    final wash = scheme.surface.withValues(
      alpha: flat
          ? 1.0
          : t.isDark
          ? 0.94
          : 0.97,
    );

    return GlassSurface(
      fill: wash,
      blur: t.blurDialog,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: t.strokeStrong),
      shadow: t.elevation.window,
      child: child,
    );
  }
}

/// 全应用模态对话框的唯一入口，与 [showGlassMenu] 对称。
///
/// 出现 120ms 向下 4px 淡入，关闭 100ms 向上 4px 淡出。设计稿 1.4f 明确写了
/// 「不做缩放、不做弹性曲线」，所以这里没有 `ScaleTransition`。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    // showGeneralDialog 只有一个时长参数，出入用同一个；120 与 100 的差值在
    // 这里不值得为它自己搭一条 route。
    transitionDuration: reduced ? Duration.zero : AppMotion.overlayIn,
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standard,
        reverseCurve: AppMotion.standard,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          // 只动 4px 以内的位移。
          position: Tween<Offset>(
            begin: const Offset(0, -0.012),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
