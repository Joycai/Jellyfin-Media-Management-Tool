import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';

/// 6.2 · 强调色取色浮层（设计稿画板 08b）。
///
/// 锚定在「＋」按钮右下、间距 8，宽 312。取色**实时预览到整个界面** —— 强调色
/// 渗进标签页底、焦点环、任务徽标和窗口底，光在一个 34 见方的色块里看它等于没
/// 看。代价是取消必须真的回滚，所以打开时先记下原值，Esc / 取消都写回去。
///
/// 两处按占位处理，见 backlog：
/// * **透明度轨**：主题令牌存的是一个不透明强调色，所有半透明变体都由它推导。
///   存一个本身带 alpha 的强调色会让每一处推导都再乘一次 alpha，对比度随之塌掉。
/// * **吸管**：要抓屏幕像素，三个平台各一套原生实现。
Future<void> showAccentPicker(
  BuildContext context, {
  required RenderBox anchor,
}) {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsService>();
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final topLeft = anchor.localToGlobal(
    Offset(0, anchor.size.height + AppSpacing.sm),
    ancestor: overlay,
  );

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.accentPickerTitle,
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.respecting(context, AppMotion.overlayIn),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, _) {
      final size = MediaQuery.sizeOf(dialogContext);
      // 贴着锚点右缘对齐，但不许越出窗口 —— 「＋」就在右列的右边缘上。
      final left = math.max(
        AppSpacing.sm,
        math.min(
          topLeft.dx + anchor.size.width - _AccentPickerPanel.width,
          size.width - _AccentPickerPanel.width - AppSpacing.sm,
        ),
      );
      return Stack(
        children: [
          Positioned(
            left: left,
            top: topLeft.dy,
            child: FadeTransition(
              opacity: animation,
              child: Material(
                type: MaterialType.transparency,
                child: ChangeNotifierProvider<SettingsService>.value(
                  value: settings,
                  child: const _AccentPickerPanel(),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _AccentPickerPanel extends StatefulWidget {
  const _AccentPickerPanel();

  /// 设计稿写死的 312：色相轨要够长才好对准一个色相。
  static const double width = 312;

  @override
  State<_AccentPickerPanel> createState() => _AccentPickerPanelState();
}

class _AccentPickerPanelState extends State<_AccentPickerPanel> {
  /// 打开那一刻的强调色。取消就是把它写回去。
  late final int? _original;

  late HSVColor _hsv;
  late final TextEditingController _hex;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _original = settings.accentColor;
    final start = Color(_original ?? AppTheme.accentPresets.first.toARGB32());
    _hsv = HSVColor.fromColor(start);
    _hex = TextEditingController(text: _formatHex(start));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _hex.dispose();
    _focus.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  static String _formatHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  /// 实时预览：每一次拖动都真的换掉整个界面的强调色，`remember: false` 所以
  /// 中间色不会挤进「最近使用」。
  void _preview(HSVColor next) {
    setState(() {
      _hsv = next;
      _hex.text = _formatHex(_hsv.toColor());
    });
    context.read<SettingsService>().setAccentColor(_hsv.toColor().toARGB32());
  }

  /// `#RGB` / `#RRGGBB` / `rgb(r,g,b)`。非法输入回退上一值 —— 输入框里边打边解析
  /// 的话，`#5` 会先被读成某个颜色，界面在你打完之前就闪过三四种底色。
  void _commitHex(String raw) {
    final parsed = _parseColor(raw);
    if (parsed == null) {
      _hex.text = _formatHex(_color);
      return;
    }
    _preview(HSVColor.fromColor(parsed));
  }

  static Color? _parseColor(String raw) {
    var s = raw.trim().toLowerCase();
    final rgb = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(s);
    if (rgb != null) {
      final parts = rgb
          .group(1)!
          .split(RegExp(r'[,\s/]+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length < 3) return null;
      final channels = <int>[];
      for (final part in parts.take(3)) {
        final v = int.tryParse(part);
        if (v == null || v < 0 || v > 255) return null;
        channels.add(v);
      }
      return Color.fromARGB(255, channels[0], channels[1], channels[2]);
    }
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = s.split('').map((c) => '$c$c').join();
    }
    if (s.length != 6) return null;
    final value = int.tryParse(s, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  void _cancel() {
    context.read<SettingsService>().setAccentColor(_original);
    Navigator.of(context).pop();
  }

  void _apply() {
    context.read<SettingsService>().setAccentColor(
      _color.toARGB32(),
      remember: true,
    );
    Navigator.of(context).pop();
  }

  void _restoreDefault() {
    context.read<SettingsService>().setAccentColor(null);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final settings = context.watch<SettingsService>();

    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _apply();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GlassSurface(
        // 不透明：取色的时候整个界面都在跟着变，浮层自己再半透明地跟着变一遍，
        // 就看不清手里这块色到底是什么颜色了。
        fill: t.isDark
            ? Color.alphaBlend(
                t.panelFill.withValues(alpha: 1),
                AppPalette.darkBase,
              )
            : Colors.white,
        blur: 0,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: t.stroke),
        shadow: t.elevation.overlay,
        padding: const EdgeInsets.all(AppSpacing.md12),
        child: SizedBox(
          width: _AccentPickerPanel.width - AppSpacing.md12 * 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SvPanel(
                hsv: _hsv,
                onChanged: (s, v) =>
                    _preview(_hsv.withSaturation(s).withValue(v)),
              ),
              const SizedBox(height: AppSpacing.md12),
              _HueTrack(
                hue: _hsv.hue,
                onChanged: (h) => _preview(_hsv.withHue(h)),
              ),
              const SizedBox(height: AppSpacing.md),
              // 透明度轨：画出来但按不动，理由见文件头。
              SettingsPlaceholderTrack(color: _color),
              const SizedBox(height: AppSpacing.md12),
              _ValueRow(
                color: _color,
                controller: _hex,
                onSubmitted: _commitHex,
              ),
              const SizedBox(height: AppSpacing.md12),
              _Recents(
                colors: settings.accentRecents,
                onPick: (argb) => _preview(HSVColor.fromColor(Color(argb))),
              ),
              const SizedBox(height: AppSpacing.md12),
              _ContrastBar(color: _color),
              const SizedBox(height: AppSpacing.md12),
              Divider(height: 1, thickness: 1, color: t.stroke),
              const SizedBox(height: AppSpacing.md12),
              Row(
                children: [
                  AppButton.ghost(
                    label: l10n.accentRestoreDefault,
                    height: AppSizes.controlSm,
                    onPressed: _restoreDefault,
                  ),
                  const Spacer(),
                  AppButton(
                    label: l10n.cancel,
                    height: AppSizes.controlSm,
                    onPressed: _cancel,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppButton.primary(
                    label: l10n.apply,
                    height: AppSizes.controlSm,
                    onPressed: _apply,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SV 面板 ─────────────────────────────────────────────────────────────────

class _SvPanel extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  const _SvPanel({required this.hsv, required this.onChanged});

  /// 6.2：SV 面板 h140。
  static const double height = 140;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void handle(Offset local) => onChanged(
          (local.dx / width).clamp(0.0, 1.0),
          1 - (local.dy / height).clamp(0.0, 1.0),
        );
        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.field),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hsv.saturation * width - 8,
                    top: (1 - hsv.value) * height - 8,
                    child: _Cursor(size: 16, fill: hsv.toColor()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Cursor extends StatelessWidget {
  final double size;
  final Color fill;

  const _Cursor({required this.size, required this.fill});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: context.tokens.elevation.row,
    ),
  );
}

// ── 色相轨 / 透明度轨 ───────────────────────────────────────────────────────

/// 轨道高 12、圆角 6，把手 18 圆白（6.2）。
const double _trackHeight = 12;
const double _trackKnob = 18;

class _HueTrack extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueTrack({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      void handle(Offset local) =>
          onChanged(((local.dx / width).clamp(0.0, 1.0)) * 360);
      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: SizedBox(
          height: _trackKnob,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: _trackHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (hue / 360 * width - _trackKnob / 2).clamp(
                  0.0,
                  width - _trackKnob,
                ),
                child: const _Knob(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 透明度轨的占位：设计稿有这条轨，令牌层还接不住带 alpha 的强调色。
class SettingsPlaceholderTrack extends StatelessWidget {
  final Color color;

  const SettingsPlaceholderTrack({super.key, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: 0.55,
      child: SizedBox(
        height: _trackKnob,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: _trackHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_trackHeight / 2),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0), color],
                ),
              ),
            ),
            const Align(alignment: Alignment.centerRight, child: _Knob()),
          ],
        ),
      ),
    ),
  );
}

class _Knob extends StatelessWidget {
  const _Knob();

  @override
  Widget build(BuildContext context) => Container(
    width: _trackKnob,
    height: _trackKnob,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: context.tokens.stroke),
      boxShadow: context.tokens.elevation.row,
    ),
  );
}

// ── 值行 ────────────────────────────────────────────────────────────────────

class _ValueRow extends StatelessWidget {
  final Color color;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _ValueRow({
    required this.color,
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Container(
          width: AppSizes.control,
          height: AppSizes.control,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadii.icon),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppTextField(
            controller: controller,
            mono: true,
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // 吸管：抓屏幕像素要三套原生实现，先画出来。
        IgnorePointer(
          child: Opacity(
            opacity: 0.55,
            child: AppIconButton(
              icon: Icons.colorize_outlined,
              tooltip: l10n.accentEyedropper,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 最近使用 ────────────────────────────────────────────────────────────────

class _Recents extends StatelessWidget {
  final List<int> colors;
  final ValueChanged<int> onPick;

  const _Recents({required this.colors, required this.onPick});

  /// 6.2：最近使用色块 22 见方 · r6。
  static const double swatch = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.accentRecents,
          style: AppTypeScale.groupLabel.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: swatch,
          child: colors.isEmpty
              ? Text(
                  l10n.accentRecentsEmpty,
                  style: AppTypeScale.caption.copyWith(color: t.textMuted),
                )
              : Row(
                  children: [
                    for (final argb in colors) ...[
                      GestureDetector(
                        onTap: () => onPick(argb),
                        child: Container(
                          width: swatch,
                          height: swatch,
                          decoration: BoxDecoration(
                            color: Color(argb),
                            borderRadius: BorderRadius.circular(AppRadii.tiny),
                            border: Border.all(color: t.stroke),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ── 对比提示条 ──────────────────────────────────────────────────────────────

/// 与深浅两套窗口底的对比度。
///
/// 强调色在这套界面里主要用作**底色**（标签页底、焦点环、进度条），所以量的是它
/// 对两套窗口底的对比，而不是它作为文字色的可读性。低于 3:1 转警告橙并注明只建议
/// 用作底色 —— 仍然允许应用：这是提示，不是门禁。
class _ContrastBar extends StatelessWidget {
  final Color color;

  const _ContrastBar({required this.color});

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final onDark = _contrast(color, AppPalette.darkBase);
    final onLight = _contrast(color, AppPalette.lightBase);
    final weak = math.min(onDark, onLight) < 3.0;
    final tint = weak ? t.warning : t.success;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.icon),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(
            weak ? Icons.warning_amber_rounded : Icons.check,
            size: 13,
            color: weak ? t.warningText : t.successText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              weak
                  ? l10n.accentContrastWeak(
                      onDark.toStringAsFixed(1),
                      onLight.toStringAsFixed(1),
                    )
                  : l10n.accentContrastOk(
                      onDark.toStringAsFixed(1),
                      onLight.toStringAsFixed(1),
                    ),
              style: AppTypeScale.caption.copyWith(color: t.textBody),
            ),
          ),
        ],
      ),
    );
  }
}
