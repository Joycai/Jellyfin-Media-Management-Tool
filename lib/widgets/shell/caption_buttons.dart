import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/design_tokens.dart';
import 'window_state.dart';

/// Windows 窗口按钮：46 × 48，**无圆角、贴边**。
///
/// 悬停底色铺满整个矩形而不是画一个圆角块 —— 设计稿 2.2 说得很直白，这是它与
/// 左侧 32×32 圆角动作按钮唯一也是最强的区分信号。把它做成圆角，用户就会把
/// 「关闭」当成又一个应用内按钮。
///
/// 命中区顶到 y=0、右到 x=0：最大化时按钮覆盖屏幕角落，Fitts 定律意义上的无限
/// 大目标。图标是 10×10、线宽 1 的矢量，不用字体图标 —— Material 的
/// `close/crop_square/remove` 视觉重量和 Windows 原生的细线条差得太远。
class WindowCaptionButtons extends StatelessWidget {
  final WindowStateNotifier window;

  const WindowCaptionButtons({super.key, required this.window});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: AppSizes.topBar,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionButton(
            tooltip: l10n.windowMinimize,
            painter: const _MinimizeIcon(),
            onPressed: window.minimize,
          ),
          _CaptionButton(
            tooltip: window.isMaximized
                ? l10n.windowRestore
                : l10n.windowMaximize,
            painter: window.isMaximized
                ? const _RestoreIcon()
                : const _MaximizeIcon(),
            onPressed: window.toggleMaximize,
          ),
          _CaptionButton(
            tooltip: l10n.windowClose,
            painter: const _CloseIcon(),
            isClose: true,
            onPressed: window.close,
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final String tooltip;
  final CustomPainter painter;
  final VoidCallback onPressed;
  final bool isClose;

  const _CaptionButton({
    required this.tooltip,
    required this.painter,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final window = WindowStateScope.of(context);

    final Color fill;
    if (widget.isClose && (_hover || _pressed)) {
      fill = _pressed ? AppPalette.closePressed : AppPalette.closeHover;
    } else if (_pressed) {
      fill = t.captionPressed;
    } else if (_hover) {
      fill = t.captionHover;
    } else {
      fill = Colors.transparent;
    }

    // 失焦时图标降到 38%，但悬停时立刻恢复满对比。
    final iconColor = widget.isClose && (_hover || _pressed)
        ? Colors.white
        : (!window.isFocused && !_hover)
        ? t.captionIcon.withValues(alpha: 0.38)
        : t.captionIcon;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 控件上的双击与右键不冒泡到拖拽层：吞掉它们，否则双击关闭按钮会
          // 顺带把窗口最大化。
          onDoubleTap: () {},
          onSecondaryTap: () {},
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AppMotion.respecting(context, AppMotion.hover),
            curve: Curves.linear,
            width: AppSizes.captionButtonWidth,
            height: AppSizes.topBar,
            color: fill,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _Recolored(widget.painter, iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把颜色注入到几何图标里，省得每个图标各写一份颜色分支。
class _Recolored extends CustomPainter {
  final CustomPainter inner;
  final Color color;

  const _Recolored(this.inner, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // 用 saveLayer + srcIn 会多一个离屏层；这里改成把画笔颜色透过
    // `_IconPainter` 传下去。
    (inner as _IconPainter).paintWith(canvas, size, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Recolored old) =>
      old.color != color || old.inner.runtimeType != inner.runtimeType;
}

abstract class _IconPainter extends CustomPainter {
  const _IconPainter();

  void paintWith(Canvas canvas, Size size, Color color);

  @override
  void paint(Canvas canvas, Size size) => paintWith(canvas, size, Colors.white);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;

  Paint stroke(Color color) => Paint()
    ..color = color
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke
    ..isAntiAlias = false;
}

class _MinimizeIcon extends _IconPainter {
  const _MinimizeIcon();

  @override
  void paintWith(Canvas canvas, Size size, Color color) {
    final y = (size.height / 2).roundToDouble() - 0.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke(color));
  }
}

class _MaximizeIcon extends _IconPainter {
  const _MaximizeIcon();

  @override
  void paintWith(Canvas canvas, Size size, Color color) {
    canvas.drawRect(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      stroke(color),
    );
  }
}

/// 还原：两个错开的方框，与 Windows 的 `` 一致。
class _RestoreIcon extends _IconPainter {
  const _RestoreIcon();

  @override
  void paintWith(Canvas canvas, Size size, Color color) {
    final p = stroke(color);
    canvas.drawRect(
      Rect.fromLTWH(0.5, 2.5, size.width - 3, size.height - 3),
      p,
    );
    final path = Path()
      ..moveTo(2.5, 2.0)
      ..lineTo(2.5, 0.5)
      ..lineTo(size.width - 0.5, 0.5)
      ..lineTo(size.width - 0.5, size.height - 2.5)
      ..lineTo(size.width - 2.0, size.height - 2.5);
    canvas.drawPath(path, p);
  }
}

class _CloseIcon extends _IconPainter {
  const _CloseIcon();

  @override
  void paintWith(Canvas canvas, Size size, Color color) {
    final p = stroke(color)..isAntiAlias = true;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), p);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), p);
  }
}
