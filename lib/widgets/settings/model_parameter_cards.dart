import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import 'context_window_scale.dart';
import 'context_window_slider.dart';
import 'settings_controls.dart';

/// 6.1 / 03b · 模型参数的两张卡：上下文窗口（滑块 + 数值输入）与最大输出。
///
/// 03b 原本把它们排在一张展开页上；渠道 × 线路 × 模型的重设计把上下文放进模型
/// 作用域、把最大输出放进线路作用域（ModelEdit 画板），两张卡本身不变。

// ── 上下文窗口卡 ────────────────────────────────────────────────────────────

class ContextWindowCard extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final int? detectedCeiling;

  const ContextWindowCard({
    super.key,
    required this.value,
    required this.onChanged,
    required this.detectedCeiling,
  });

  @override
  State<ContextWindowCard> createState() => _ContextWindowCardState();
}

class _ContextWindowCardState extends State<ContextWindowCard> {
  late final TextEditingController _field;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: widget.value?.toString() ?? '');
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(_field.text);
    });
  }

  @override
  void didUpdateWidget(ContextWindowCard old) {
    super.didUpdateWidget(old);
    // 滑块动了就把输入框同步过去 —— 但正在里面打字时不动它。
    if (widget.value != old.value && !_focus.hasFocus) {
      _field.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 回车或失焦时生效：向最近的 1k 对齐，越界夹到端点，非法字符回退上一有效值。
  /// 边打边解析的话，`13` 会先被当成 13 tokens 夹到 8192，光标还在框里数字就跳了。
  void _commit(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      widget.onChanged(null);
      _field.text = '';
      return;
    }
    final parsed = int.tryParse(text);
    if (parsed == null) {
      _field.text = widget.value?.toString() ?? '';
      return;
    }
    final tokens = ContextWindowScale.align(parsed);
    _field.text = tokens.toString();
    widget.onChanged(tokens);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final value = widget.value;
    final ceiling = widget.detectedCeiling;
    final over = value != null && ceiling != null && value > ceiling;

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                l10n.contextWindow,
                style: AppTypeScale.controlStrong.copyWith(color: t.textTitle),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.contextWindowScaleHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tokens.monoTiny.copyWith(color: t.textMuted),
                ),
              ),
              Text(
                value == null
                    ? l10n.contextWindowHint
                    : ContextWindowScale.grouped(value),
                style: context.tokens.monoBody.copyWith(color: t.accentText),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
          Row(
            children: [
              Expanded(
                child: ContextWindowSlider(
                  value: value,
                  onChanged: widget.onChanged,
                  detectedCeiling: ceiling,
                ),
              ),
              const SizedBox(width: AppSpacing.md12),
              SizedBox(
                // 03b 的 150 宽数值输入。
                width: 150,
                child: AppTextField(
                  controller: _field,
                  focusNode: _focus,
                  mono: true,
                  hint: l10n.contextWindowHint,
                  onSubmitted: _commit,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(right: 150 + AppSpacing.md12),
            child: ContextWindowTickLabels(value: value),
          ),
          const SizedBox(height: AppSpacing.md12),
          Divider(height: 1, thickness: 1, color: t.stroke),
          SettingsFootnote(l10n.contextWindowFootnote),
          if (over)
            Text(
              l10n.contextWindowOverDetected(
                ContextWindowScale.grouped(ceiling),
              ),
              style: AppTypeScale.caption.copyWith(color: t.warningText),
            ),
        ],
      ),
    );
  }
}

// ── 最大输出卡 ──────────────────────────────────────────────────────────────

class MaxOutputCard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final int? contextWindow;

  const MaxOutputCard({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.contextWindow,
  });

  @override
  State<MaxOutputCard> createState() => _MaxOutputCardState();
}

class _MaxOutputCardState extends State<MaxOutputCard> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(widget.controller.text);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// 夹紧在失焦 / 回车时做，不在每一次按键上做：打 2048 的路上会先经过 2，
  /// 那一刻夹到 256 会把用户正在打的数字改掉。
  void _commit(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) return;
    final clamped = MaxOutputScale.clamp(
      parsed,
      contextWindow: widget.contextWindow,
    ).toString();
    if (clamped == widget.controller.text) return;
    widget.controller.text = clamped;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  l10n.maxOutputTokens,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.controlStrong.copyWith(
                    color: t.textTitle,
                  ),
                ),
              ),
              Text(
                l10n.maxOutputStep,
                style: context.tokens.monoTiny.copyWith(color: t.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
          AppTextField(
            controller: widget.controller,
            focusNode: _focus,
            mono: true,
            hint: l10n.maxOutputTokensHint,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => widget.onChanged(),
            onSubmitted: _commit,
          ),
          const SizedBox(height: AppSpacing.md12),
          Divider(height: 1, thickness: 1, color: t.stroke),
          SettingsFootnote(l10n.maxOutputFootnote),
        ],
      ),
    );
  }
}

// ── 告示条 ──────────────────────────────────────────────────────────────────

class ParameterNotice extends StatelessWidget {
  final String text;
  final Color tint;

  const ParameterNotice({super.key, required this.text, required this.tint});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md12,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: tint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: AppTypeScale.caption.copyWith(
                color: t.textBody,
                height: AppTypeScale.leadingBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
