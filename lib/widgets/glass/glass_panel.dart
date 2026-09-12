import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../ui/glass_surface.dart';

/// 玻璃面板。
///
/// 现在只是 [GlassSurface] 的一层薄封装 —— 模糊的三条规矩（底色不透明就丢掉
/// 滤镜、性能模式整块跳过、没有裁剪不开模糊）都收在那一个地方，这里只负责把
/// 面板的默认取值从 [AppTokens] 取出来。
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// 用侧栏 / 面板的底色，而不是卡片底色。
  final bool sidebar;
  final Color? fill;

  /// 用渐变代替纯色底（中央表格那种蓝→绿斜向washes）。描边与模糊照旧。
  final Gradient? gradient;

  /// L2 投影。贴边的列不开。
  final bool elevated;

  /// 是否加背景模糊。**要求它不等于拿到它**：不透明的 [fill] / [gradient] 会把
  /// 模糊结果整块盖住，那时滤镜会被丢弃。见 [GlassSurface]。
  final bool blur;

  /// 发丝描边在每一边都吃掉布局空间：撑满面板的子节点拿到的是面板宽减去它的
  /// 两倍。任何拿面板外约束量自己的东西都要减掉，否则正好宽出 `2 * borderWidth`。
  static const borderWidth = 1.0;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppRadii.panel,
    this.sidebar = false,
    this.fill,
    this.gradient,
    this.elevated = false,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final resolvedFill = fill ?? (sidebar ? t.panelFill : t.cardFill);
    final borderRadius = BorderRadius.circular(radius);

    // 渐变要自己画：GlassSurface 只吃纯色底（它判断「底色是否遮住背景」也靠
    // 单一颜色）。不透明的渐变同样要跳过模糊，理由一模一样。
    if (gradient != null) {
      final opaque = gradient!.colors.every((c) => c.a >= 0.995);
      return GlassSurface(
        fill: opaque ? const Color(0xFFFFFFFF) : Colors.transparent,
        blur: opaque ? 0 : (blur ? t.blurPanel : 0),
        borderRadius: borderRadius,
        shadow: elevated ? t.elevation.card : const [],
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: borderRadius,
            border: Border.all(color: t.stroke, width: borderWidth),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      );
    }

    return GlassSurface(
      fill: resolvedFill,
      blur: blur ? t.blurPanel : 0,
      borderRadius: borderRadius,
      border: Border.all(color: t.stroke, width: borderWidth),
      shadow: elevated ? t.elevation.card : const [],
      padding: padding,
      child: child,
    );
  }
}
