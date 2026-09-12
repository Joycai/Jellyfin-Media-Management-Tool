import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shortcuts/app_shortcuts.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import 'settings_controls.dart';

/// 6.2 · 快捷键（设计稿画板 23）。
///
/// 整页从 [appShortcuts] 渲染，所以它永远不会和实际生效的绑定说两套话 —— 加一个
/// 快捷键就是那份列表里加一行，这里跟着多一行。
///
/// 设计稿的「点击任意按键组合即可改绑」还做不到（绑定是编译期常量，不是配置），
/// 所以「恢复默认」画成占位；搜索框是真的：它筛的是命令名和键位文本两边。
class ShortcutsSection extends StatefulWidget {
  const ShortcutsSection({super.key});

  @override
  State<ShortcutsSection> createState() => _ShortcutsSectionState();
}

class _ShortcutsSectionState extends State<ShortcutsSection> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _groupLabel(AppLocalizations l10n, AppShortcutGroup group) =>
      switch (group) {
        AppShortcutGroup.navigation => l10n.shortcutGroupNavigation,
        AppShortcutGroup.selection => l10n.shortcutGroupSelection,
        AppShortcutGroup.files => l10n.shortcutGroupFiles,
        AppShortcutGroup.app => l10n.shortcutGroupApp,
      };

  bool _matches(AppShortcut shortcut, AppLocalizations l10n) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (shortcut.describe(l10n).toLowerCase().contains(q)) return true;
    return shortcut.activators.any(
      (a) => formatActivator(a).toLowerCase().contains(q),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final all = appShortcuts().where((s) => _matches(s, l10n)).toList();

    return SettingsPage(
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _search,
                icon: Icons.search,
                hint: l10n.shortcutsSearchHint,
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const SizedBox(width: AppSpacing.md12),
            SettingsPlaceholder(
              child: SettingsMiniButton(l10n.shortcutsRestoreDefaults),
            ),
          ],
        ),
        SettingsFootnote(l10n.shortcutsRebindHint),
        const SizedBox(height: AppSpacing.xl),
        if (all.isEmpty)
          SettingsCard(
            child: Text(
              l10n.shortcutsNoMatch,
              style: AppTypeScale.control.copyWith(
                color: context.tokens.textMuted,
              ),
            ),
          )
        else
          for (final group in AppShortcutGroup.values)
            if (all.any((s) => s.group == group)) ...[
              SettingsSectionTitle(_groupLabel(l10n, group)),
              SettingsRowsCard(
                children: [
                  for (final shortcut in all.where((s) => s.group == group))
                    _ShortcutRow(shortcut: shortcut),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
        SettingsFootnote(l10n.shortcutsPlatformNote),
        SettingsFootnote(l10n.shortcutsHint),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final AppShortcut shortcut;
  const _ShortcutRow({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortcut.describe(l10n),
              style: AppTypeScale.control.copyWith(color: t.textTitle),
            ),
          ),
          const SizedBox(width: AppSpacing.md12),
          // 每一个别名都列出来，不只列主键位 —— 发现不了的别名等于不存在。
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final activator in shortcut.activators)
                ShortcutPill(formatActivator(activator)),
            ],
          ),
        ],
      ),
    );
  }
}
