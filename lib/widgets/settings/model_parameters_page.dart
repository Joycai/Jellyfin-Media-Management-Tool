import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import 'context_window_scale.dart';
import 'context_window_slider.dart';
import 'settings_controls.dart';

/// 6.1 · 模型参数展开页（设计稿画板 03b）。
///
/// 从服务详情页的「模型参数」摘要行展开，占满内容区（服务列表让位）—— 上下文
/// 滑块要一整条轨道才有用，塞在 360 + 详情的右半边里刻度会挤成一团。
///
/// 页面只管版式：值都还在服务详情那边的控制器上，改动照旧走它的 `_persist`。
class ModelParametersPage extends StatelessWidget {
  final String serviceName;
  final String model;

  /// null = 留空 = 不限制。
  final int? contextWindow;
  final ValueChanged<int?> onContextWindow;

  final TextEditingController maxOutput;
  final VoidCallback onMaxOutputChanged;

  /// 服务端上报的上下文上限，测过连接才有。
  final int? detectedCeiling;

  final VoidCallback onCollapse;

  /// 采样参数卡。留在服务详情那边（它要读家族预设和上次测试结果），这里只是把
  /// 它排进设计稿给的位置。
  final Widget sampling;

  const ModelParametersPage({
    super.key,
    required this.serviceName,
    required this.model,
    required this.contextWindow,
    required this.onContextWindow,
    required this.maxOutput,
    required this.onMaxOutputChanged,
    required this.detectedCeiling,
    required this.onCollapse,
    required this.sampling,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(serviceName: serviceName, model: model, onCollapse: onCollapse),
        Expanded(
          child: SettingsPage(
            children: [
              SettingsColumns(
                // 设计稿 `1.9fr 1fr`：滑块要的是长度。
                leftFlex: 190,
                left: _ContextCard(
                  value: contextWindow,
                  onChanged: onContextWindow,
                  detectedCeiling: detectedCeiling,
                ),
                right: _MaxOutputCard(
                  controller: maxOutput,
                  onChanged: onMaxOutputChanged,
                  contextWindow: contextWindow,
                ),
              ),
              const SizedBox(height: AppSpacing.md12),
              _NoticeBar(text: l10n.contextWindowNote, tint: t.warning),
              const SizedBox(height: AppSpacing.md12),
              sampling,
            ],
          ),
        ),
      ],
    );
  }
}

// ── 顶条 ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String serviceName;
  final String model;
  final VoidCallback onCollapse;

  const _Header({
    required this.serviceName,
    required this.model,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Container(
      height: AppSizes.topBar,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.stroke)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${l10n.secAiServices} · $serviceName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.control.copyWith(color: t.textMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.chevron_right, size: 14, color: t.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.modelParameters,
            style: AppTypeScale.title.copyWith(color: t.textTitle),
          ),
          if (model.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.md),
            AppTag.neutral(model, mono: true),
          ],
          const Spacer(),
          // 「保存」不在这里：每一处改动落键即存（服务详情的 `_persist`），
          // 摆一个保存按钮会让人以为不按就丢。设计稿的那颗按钮因此换成收起。
          AppButton(
            label: l10n.modelParametersCollapse,
            icon: Icons.expand_less,
            height: AppSizes.controlSm,
            onPressed: onCollapse,
          ),
        ],
      ),
    );
  }
}

// ── 上下文窗口卡 ────────────────────────────────────────────────────────────

class _ContextCard extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final int? detectedCeiling;

  const _ContextCard({
    required this.value,
    required this.onChanged,
    required this.detectedCeiling,
  });

  @override
  State<_ContextCard> createState() => _ContextCardState();
}

class _ContextCardState extends State<_ContextCard> {
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
  void didUpdateWidget(_ContextCard old) {
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
                  style: AppTypeScale.monoTiny.copyWith(color: t.textMuted),
                ),
              ),
              Text(
                value == null
                    ? l10n.contextWindowHint
                    : ContextWindowScale.grouped(value),
                style: AppTypeScale.monoBody.copyWith(color: t.accentText),
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

class _MaxOutputCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final int? contextWindow;

  const _MaxOutputCard({
    required this.controller,
    required this.onChanged,
    required this.contextWindow,
  });

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
                style: AppTypeScale.monoTiny.copyWith(color: t.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md12),
          AppTextField(
            controller: controller,
            mono: true,
            hint: l10n.maxOutputTokensHint,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => onChanged(),
            // 夹紧在失焦 / 回车时做，不在每一次按键上做：打 2048 的路上会先经过
            // 2，那一刻夹到 256 会把用户正在打的数字改掉。
            onSubmitted: (raw) {
              final parsed = int.tryParse(raw.trim());
              if (parsed == null) return;
              controller.text = MaxOutputScale.clamp(
                parsed,
                contextWindow: contextWindow,
              ).toString();
              onChanged();
            },
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

class _NoticeBar extends StatelessWidget {
  final String text;
  final Color tint;

  const _NoticeBar({required this.text, required this.tint});

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

/// 服务详情里的「模型参数」摘要行：标题 + 一排 chips + 右侧「展开 ▾」。
class ModelParametersSummary extends StatelessWidget {
  final int? contextWindow;
  final int? maxOutput;
  final String presetLabel;
  final bool thinking;
  final VoidCallback onExpand;

  const ModelParametersSummary({
    super.key,
    required this.contextWindow,
    required this.maxOutput,
    required this.presetLabel,
    required this.thinking,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return SettingsCard(
      child: Row(
        children: [
          Text(
            l10n.modelParameters,
            style: AppTypeScale.controlStrong.copyWith(color: t.textTitle),
          ),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                AppTag.neutral(
                  contextWindow == null
                      ? l10n.contextWindowHint
                      : ContextWindowScale.format(contextWindow!),
                  mono: true,
                ),
                if (maxOutput != null)
                  AppTag.neutral('↑ $maxOutput', mono: true),
                AppTag.neutral(presetLabel),
                if (thinking)
                  AppTag(label: l10n.thinkingMode, color: AppPalette.ai),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md12),
          AppButton(
            label: l10n.modelParametersExpand,
            icon: Icons.expand_more,
            height: AppSizes.controlSm,
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}
