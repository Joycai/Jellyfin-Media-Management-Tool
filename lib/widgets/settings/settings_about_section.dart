import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/gpu_info.dart';
import '../../theme/design_tokens.dart';
import '../ui/app_controls.dart';
import 'settings_controls.dart';

/// 6.4 · 关于（设计稿画板 24）。
///
/// 设计稿的构建信息里有提交号、分支和提交时间 —— 那些要在打包时注入，现在没有。
/// 按「画出来、标注、不假装」的规矩，这三行照旧占位显示 `—`，并在卡底说清原因；
/// 悄悄删掉它们会让人以为这份构建信息本就只有这么多。
class AboutSection extends StatelessWidget {
  /// `X.Y.Z+N`，由 sync-version 技能写入 [SettingsScreen]。
  final String version;

  const AboutSection({super.key, required this.version});

  static const String _repoUrl =
      'https://github.com/Joycai/Jellyfin-Media-Management-Tool';
  static const String _namingDocs =
      'https://jellyfin.org/docs/general/server/media/naming/';

  String get _versionName => version.split('+').first;
  String get _buildNumber =>
      version.contains('+') ? version.split('+').last : '—';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsPage(
      children: [
        _Header(version: _versionName),
        const SizedBox(height: AppSpacing.xl),
        SettingsColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionTitle(
                l10n.aboutBuildInfo,
                trailing: SettingsMiniButton(
                  l10n.privacyCopyPath,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: '$version · ${_runtime()}'),
                    );
                  },
                ),
              ),
              SettingsRowsCard(
                children: [
                  _InfoRow(l10n.aboutVersion, _versionName),
                  _InfoRow(l10n.aboutBuildNumber, _buildNumber),
                  // 打包时还没有注入 git 元数据 —— 见卡底说明。
                  _InfoRow(l10n.aboutCommit, '—', dim: true),
                  _InfoRow(l10n.aboutBranch, '—', dim: true),
                  _InfoRow(l10n.aboutRuntime, _runtime()),
                ],
              ),
              SettingsFootnote(l10n.aboutBuildInfoPlaceholder),
              const SizedBox(height: AppSpacing.xl),
              SettingsSectionTitle(l10n.aboutSystem),
              SettingsRowsCard(
                children: [
                  _InfoRow(l10n.aboutOs, _os()),
                  _InfoRow(l10n.aboutArch, _arch()),
                ],
              ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionTitle(l10n.aboutOpenSource),
              SettingsRowsCard(
                children: [
                  _InfoRow(l10n.aboutLicense, 'MIT'),
                  _LinkRow(
                    label: l10n.aboutRepository,
                    value: 'github.com/Joycai',
                    url: _repoUrl,
                  ),
                  _LinkRow(
                    label: l10n.aboutIssues,
                    value: 'Issues',
                    url: '$_repoUrl/issues',
                  ),
                  _LinkRow(
                    label: l10n.aboutJellyfinNaming,
                    value: 'jellyfin.org',
                    url: _namingDocs,
                  ),
                  _InfoRow(l10n.aboutCopyright, l10n.aboutCopyrightValue),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _GraphicsSection(),
            ],
          ),
        ),
      ],
    );
  }

  /// Flutter / Dart 版本不是运行期可读的，Dart 版本是 —— 只报能报的那个。
  String _runtime() {
    final dart = Platform.version.split(' ').first;
    return 'Dart $dart';
  }

  String _os() => Platform.operatingSystemVersion;

  /// Dart 把自己的目标三元组印在 `Platform.version` 末尾（`on "windows_x64"`），
  /// 这是运行期唯一能拿到架构的地方 —— 没有匹配上就报 `—`，不猜。
  String _arch() =>
      RegExp(r'on "([a-z0-9_]+)"').firstMatch(Platform.version)?.group(1) ??
      '—';
}

// ── 头 ──────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String version;
  const _Header({required this.version});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return SettingsCard(
      child: Row(
        children: [
          Container(
            width: AppSizes.controlXs * 2,
            height: AppSizes.controlXs * 2,
            decoration: BoxDecoration(
              gradient: t.brandGradient,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            alignment: Alignment.center,
            child: Text(
              'J',
              style: AppTypeScale.heading.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.appBrand,
                  style: AppTypeScale.title.copyWith(color: t.textTitle),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.aboutTagline} · v $version',
                  style: AppTypeScale.caption.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          SettingsPlaceholder(child: SettingsMiniButton(l10n.aboutChangelog)),
          const SizedBox(width: AppSpacing.sm),
          SettingsPlaceholder(
            child: SettingsMiniButton(l10n.aboutCheckUpdates),
          ),
        ],
      ),
    );
  }
}

// ── 行 ──────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  /// 未注入的字段：值压成禁用色，免得 `—` 看起来像真的读出来是空的。
  final bool dim;

  const _InfoRow(this.label, this.value, {this.dim = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypeScale.control.copyWith(color: t.textSecondary),
          ),
          const SizedBox(width: AppSpacing.md12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.monoSmall.copyWith(
                color: dim ? t.textDisabled : t.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final String value;
  final String url;

  const _LinkRow({required this.label, required this.value, required this.url});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypeScale.control.copyWith(color: t.textSecondary),
          ),
          const Spacer(),
          AppButton.ghost(
            label: value,
            icon: Icons.open_in_new,
            height: AppSizes.controlSm,
            onPressed: () => launchUrl(Uri.parse(url)),
          ),
        ],
      ),
    );
  }
}

// ── 图形设备 ────────────────────────────────────────────────────────────────

/// 设计稿在这里画的是「每块 GPU 一行 + 当前运行 / 空闲」。
/// [GpuInfo] 只报进程实际拿到的那一块（DXGI 的默认适配器），所以只有一行，而它
/// 就是「当前运行」的那一块 —— 报不出来的第二块不会凭空写上去。
class _GraphicsSection extends StatelessWidget {
  const _GraphicsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    // 非 Windows，或 DXGI 查询失败：整块不出现，而不是道歉。
    final gpu = GpuInfo.current();
    if (gpu == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.aboutGraphics),
        SettingsRowsCard(
          children: [
            SettingsRow(
              leading: const SettingsRowIcon(Icons.memory_outlined),
              title: gpu.name,
              subtitle: gpu.dedicatedMemoryBytes > 0
                  ? GpuInfo.formatBytes(gpu.dedicatedMemoryBytes)
                  : l10n.aboutGpuShared,
              subtitleMono: false,
              trailing: [AppTag(label: l10n.aboutGpuRunning, color: t.success)],
            ),
          ],
        ),
        SettingsFootnote(l10n.aboutGpuHint),
      ],
    );
  }
}
