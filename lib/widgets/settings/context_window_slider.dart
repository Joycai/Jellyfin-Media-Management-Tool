import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/design_tokens.dart';
import 'context_window_scale.dart';

/// 6.1 / 03c · 上下文窗口滑块。
///
/// 轨 h6 · r3，已填品牌渐变，九个 2×4 刻度点，把手 18 圆白。四种把手状态照设计
/// 稿：默认实白、悬停 5px 光环、拖拽强调色实底 + 数值气泡、空值空心。
///
/// 空值（= 不限制）不是「0」：滑轨整条降到 40% 不透明、把手空心，因为此时轨道上
/// 任何一个位置都不代表当前设置 —— 画一个停在最左边的实心把手会读成「已经设成
/// 8k 了」。
class ContextWindowSlider extends StatefulWidget {
  /// null = 留空 = 不限制。
  final int? value;
  final ValueChanged<int?> onChanged;

  /// 服务端上报的上限。超出的刻度段转警告橙 —— 仍然允许保存。
  final int? detectedCeiling;

  const ContextWindowSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.detectedCeiling,
  });

  /// 1.3c 之外的一次性取值，来自 03c：轨 6 / 刻度点 2×4 / 把手 18。
  static const double trackHeight = 6;
  static const double tickWidth = 2;
  static const double tickHeight = 4;
  static const double knob = 18;

  /// 整条控件的高度。写死而不是量出来，是为了让它能被 `IntrinsicHeight` 问：
  /// 里头的 `LayoutBuilder` 拿不出固有尺寸（debug 下直接抛），而一个紧约束的
  /// `SizedBox` 会在到达它之前就把答案给出去。
  static const double height = knob + AppSpacing.xxs;

  @override
  State<ContextWindowSlider> createState() => _ContextWindowSliderState();
}

class _ContextWindowSliderState extends State<ContextWindowSlider> {
  bool _hover = false;
  bool _dragging = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _effective => widget.value ?? ContextWindowScale.min;

  void _emit(int tokens) => widget.onChanged(ContextWindowScale.snap(tokens));

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final delta = shift
        ? ContextWindowScale.coarseStep
        : ContextWindowScale.step;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowDown:
        _emit(ContextWindowScale.align(_effective - delta));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowUp:
        _emit(ContextWindowScale.align(_effective + delta));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        _emit(ContextWindowScale.nextTick(_effective, up: true));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        _emit(ContextWindowScale.nextTick(_effective, up: false));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _emit(ContextWindowScale.min);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _emit(ContextWindowScale.max);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unset = widget.value == null;
    final position = ContextWindowScale.positionOf(_effective);
    final ceiling = widget.detectedCeiling;

    return SizedBox(
      height: ContextWindowSlider.height,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 把手是圆的，圆心不能跑到轨道端点之外，所以可走的距离比轨道短一个
              // 把手宽 —— 不减这一下，两端的值就永远选不中。
              final travel = constraints.maxWidth - ContextWindowSlider.knob;

              void handle(Offset local) {
                _focus.requestFocus();
                final x = (local.dx - ContextWindowSlider.knob / 2).clamp(
                  0.0,
                  travel,
                );
                widget.onChanged(
                  ContextWindowScale.tokensAt(travel == 0 ? 0 : x / travel),
                );
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) {
                  setState(() => _dragging = true);
                  handle(d.localPosition);
                },
                onPanUpdate: (d) => handle(d.localPosition),
                onPanEnd: (_) => setState(() => _dragging = false),
                onPanCancel: () => setState(() => _dragging = false),
                child: SizedBox(
                  height: ContextWindowSlider.height,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Opacity(
                        opacity: unset ? 0.4 : 1,
                        child: _Track(
                          position: position,
                          travel: travel,
                          filled: !unset,
                          ceiling: ceiling,
                        ),
                      ),
                      Positioned(
                        left: position * travel,
                        child: _Knob(
                          hollow: unset,
                          hovered: _hover && !_dragging,
                          dragging: _dragging,
                          accent: t.accent,
                        ),
                      ),
                      if (_dragging && !unset)
                        Positioned(
                          left: (position * travel - 24).clamp(
                            0.0,
                            constraints.maxWidth - 60,
                          ),
                          bottom: 0,
                          child: _Bubble(
                            label: ContextWindowScale.format(_effective),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Track extends StatelessWidget {
  final double position;
  final double travel;
  final bool filled;
  final int? ceiling;

  const _Track({
    required this.position,
    required this.travel,
    required this.filled,
    required this.ceiling,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 服务端上限之后的那一段转警告橙：能保存，但要看得出来它超出了。
    final ceilingPosition = ceiling == null
        ? null
        : ContextWindowScale.positionOf(ceiling!);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ContextWindowSlider.knob / 2,
      ),
      child: SizedBox(
        height: ContextWindowSlider.knob,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: ContextWindowSlider.trackHeight,
              decoration: BoxDecoration(
                color: t.controlFill,
                borderRadius: BorderRadius.circular(
                  ContextWindowSlider.trackHeight / 2,
                ),
              ),
            ),
            if (ceilingPosition != null && ceilingPosition < 1)
              Positioned(
                left: ceilingPosition * travel,
                right: 0,
                child: Container(
                  height: ContextWindowSlider.trackHeight,
                  decoration: BoxDecoration(
                    color: t.warning.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(
                      ContextWindowSlider.trackHeight / 2,
                    ),
                  ),
                ),
              ),
            if (filled)
              Container(
                width: position * travel,
                height: ContextWindowSlider.trackHeight,
                decoration: BoxDecoration(
                  gradient: t.brandGradient,
                  borderRadius: BorderRadius.circular(
                    ContextWindowSlider.trackHeight / 2,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < ContextWindowScale.ticks.length; i++)
                  Container(
                    width: ContextWindowSlider.tickWidth,
                    height: ContextWindowSlider.tickHeight,
                    color: t.textMuted,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  final bool hollow;
  final bool hovered;
  final bool dragging;
  final Color accent;

  const _Knob({
    required this.hollow,
    required this.hovered,
    required this.dragging,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedContainer(
      duration: AppMotion.respecting(context, AppMotion.hover),
      width: ContextWindowSlider.knob,
      height: ContextWindowSlider.knob,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow
            ? Colors.transparent
            : dragging
            ? accent
            : Colors.white,
        border: hollow
            ? Border.all(color: t.strokeStrong, width: 2)
            : Border.all(color: t.stroke),
        boxShadow: [
          if (dragging)
            BoxShadow(
              color: accent.withValues(alpha: 0.24),
              spreadRadius: 5,
              blurRadius: 0,
            )
          else if (hovered)
            BoxShadow(
              color: accent.withValues(alpha: 0.16),
              spreadRadius: 5,
              blurRadius: 0,
            ),
          ...t.elevation.row,
        ],
      ),
    );
  }
}

/// 拖拽时把手上方的数值气泡。
class _Bubble extends StatelessWidget {
  final String label;

  const _Bubble({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        label,
        style: AppTypeScale.monoTiny.copyWith(color: t.badgeText),
      ),
    );
  }
}

/// 刻度标签行：mono 9.5px（吸到 10），当前所在段用强调色标出来。
class ContextWindowTickLabels extends StatelessWidget {
  final int? value;

  const ContextWindowTickLabels({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = value;
    // 「当前段」= 值所落的那一段的右端刻度。高亮右端而不是左端，是因为读数的时候
    // 人找的是「这大概是几 k」，而段内的值总是向上凑到那个整数。
    int? current;
    if (v != null) {
      for (final tick in ContextWindowScale.ticks) {
        if (v <= tick) {
          current = tick;
          break;
        }
      }
      current ??= ContextWindowScale.max;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ContextWindowSlider.knob / 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final tick in ContextWindowScale.ticks)
            Text(
              ContextWindowScale.format(tick),
              style: AppTypeScale.monoTiny.copyWith(
                color: tick == current ? t.accentText : t.textMuted,
                fontWeight: tick == current ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}
