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
/// 版式照画板：头一行不入卡，两张等宽信息卡并排，图形设备整行铺在下面。
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
        const _Header(),
        const SizedBox(height: AppSpacing.lg),
        SettingsColumns(
          // 24 的两张信息卡是 `1fr 1fr`，不是骨架默认的 112:100；同一行的格子
          // 等高，所以两张卡都 `Expanded` 到这一行的高度。
          leftFlex: 100,
          equalHeight: true,
          left: SettingsRowsCard(
            header: SettingsCardHeader(
              l10n.aboutBuildInfo,
              // 画板 24 把它画成卡头上的一个文字链，不是一颗描边按钮 ——
              // 幽灵按钮是这套控件里离「链接」最近的一档。
              trailing: AppButton.ghost(
                label: l10n.privacyCopyPath,
                height: AppSizes.controlXs,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: '$version · ${_runtime()} · ${_system()}',
                    ),
                  );
                },
              ),
            ),
            children: [
              _InfoRow(l10n.aboutVersion, _versionName),
              _InfoRow(l10n.aboutBuildNumber, _buildNumber),
              // 打包时还没有注入 git 元数据 —— 见卡底说明。
              _InfoRow(l10n.aboutCommit, '—', dim: true),
              _InfoRow(l10n.aboutBranch, '—', dim: true),
              _InfoRow(l10n.aboutCommitTime, '—', dim: true),
              _InfoRow(l10n.aboutRuntime, _runtime()),
              // 说明留在卡里而不是卡下：卡下的话它会把左列撑高，两张等高的卡
              // 就再也对不齐了。
              SettingsFootnote(l10n.aboutBuildInfoPlaceholder),
            ],
          ),
          right: SettingsRowsCard(
            header: SettingsCardHeader(l10n.aboutOpenSource),
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
              // 依赖清单要一个能翻的页面，而全页路由得自带二级顶栏，不是顺手
              // 能加的一行 —— 见 backlog B21。
              SettingsPlaceholder(
                child: _InfoRow(
                  l10n.aboutThirdParty,
                  l10n.comingSoon,
                  dim: true,
                ),
              ),
              _LinkRow(
                label: l10n.aboutJellyfinNaming,
                value: 'jellyfin.org',
                url: _namingDocs,
              ),
              _InfoRow(l10n.aboutCopyright, l10n.aboutCopyrightValue),
              _InfoRow(l10n.aboutSystem, _system()),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _GraphicsSection(),
      ],
    );
  }

  /// Flutter / Dart 版本不是运行期可读的，Dart 版本是 —— 只报能报的那个。
  String _runtime() {
    final dart = Platform.version.split(' ').first;
    return 'Dart $dart';
  }

  /// 设计稿把系统与架构合成一行（`macOS 15.4 · Apple Silicon`）。
  String _system() => '${_os()} · ${_arch()}';

  /// Windows 把产品名用引号裹起来（`"Windows 11 Pro" 10.0 (Build 26200)`），
  /// 那对引号在一行信息里只是噪音。
  String _os() => Platform.operatingSystemVersion.replaceAll('"', '');

  /// Dart 把自己的目标三元组印在 `Platform.version` 末尾（`on "windows_x64"`），
  /// 这是运行期唯一能拿到架构的地方 —— 没有匹配上就报 `—`，不猜。
  String _arch() =>
      RegExp(r'on "([a-z0-9_]+)"').firstMatch(Platform.version)?.group(1) ??
      '—';
}

// ── 头 ──────────────────────────────────────────────────────────────────────

/// 画板 24 的头一行不在卡里：52 的品牌方块、名字与一句话，右边两颗动作。
/// 版本号不重复写在这里 —— 顶栏和「构建信息」各有一份，第三份只是噪音。
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: AppSizes.topBar,
          height: AppSizes.topBar,
          decoration: BoxDecoration(
            gradient: t.brandGradient,
            borderRadius: BorderRadius.circular(AppRadii.panel),
            boxShadow: t.accentShadow,
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
                // 24 的产品名是 17/700；字阶上没有 17，最近的一级是 16。
                style: AppTypeScale.title.copyWith(
                  fontSize: AppTypeScale.sizeSubheading,
                  fontWeight: FontWeight.w700,
                  color: t.textTitle,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.aboutTagline,
                style: AppTypeScale.caption.copyWith(color: t.textMuted),
              ),
            ],
          ),
        ),
        SettingsPlaceholder(child: SettingsMiniButton(l10n.aboutChangelog)),
        const SizedBox(width: AppSpacing.sm),
        SettingsPlaceholder(
          child: SettingsMiniButton(l10n.aboutCheckUpdates, accent: true),
        ),
      ],
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
              style: context.tokens.monoSmall.copyWith(
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

/// 画板 24 的整行卡：一格一块适配器，进程实际用的那块打「当前运行」。
///
/// 设计稿在旁注里说单 GPU 的机器隐藏整块。这里没有照做：[GpuInfo] 存在的理由
/// 就是回答「Windows 把哪块卡给了这个应用」，而那正是 Windows 的「按应用设置
/// 显卡」改完之后要来核对的一行 —— 机器上只有一块时它依然是答案，藏掉就等于把
/// 这个诊断删了（见 backlog C12）。
class _GraphicsSection extends StatelessWidget {
  const _GraphicsSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    // 非 Windows，或 DXGI 查询失败：整块不出现，而不是道歉。
    final adapters = GpuInfo.all();
    if (adapters.isEmpty) return const SizedBox.shrink();
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题、徽标与旁注都在卡里 —— 画板 24 的这张卡自带卡头。
          SettingsCardHeader(
            l10n.aboutGraphics,
            emphasis: true,
            // 只有一块时不挂这个徽标：「检测到 1 个 GPU」什么也没告诉人。
            badge: adapters.length > 1
                ? AppTag(
                    label: l10n.aboutGpuCount(adapters.length),
                    color: t.accent,
                  )
                : null,
            trailing: Text(
              l10n.aboutGpuInfoOnly,
              style: AppTypeScale.caption.copyWith(color: t.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // 等高的一排格子。`stretch` 在 `ListView` 里交叉轴无界会直接抛，所以
          // 先用 `IntrinsicHeight` 把高度定下来 —— 同 `SettingsColumns` 的
          // `equalHeight`。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < adapters.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _GpuTile(gpu: adapters[i], running: i == 0),
                  ),
                ],
              ],
            ),
          ),
          SettingsFootnote(l10n.aboutGpuHint),
        ],
      ),
    );
  }
}

class _GpuTile extends StatelessWidget {
  final GpuInfo gpu;

  /// 列表第一项就是进程的默认适配器 —— 见 [GpuInfo]。
  final bool running;

  const _GpuTile({required this.gpu, required this.running});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md12,
        vertical: AppSpacing.md12,
      ),
      decoration: BoxDecoration(
        color: running ? t.accent.withValues(alpha: 0.10) : t.controlFill,
        borderRadius: BorderRadius.circular(AppRadii.field),
        border: Border.all(
          color: running ? t.accent.withValues(alpha: 0.28) : t.stroke,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gpu.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.controlStrong.copyWith(
                    color: t.textTitle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  gpu.dedicatedMemoryBytes > 0
                      ? GpuInfo.formatBytes(gpu.dedicatedMemoryBytes)
                      : l10n.aboutGpuShared,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tokens.monoTiny.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          running
              ? AppTag(label: l10n.aboutGpuRunning, color: t.success)
              : AppTag.neutral(l10n.aboutGpuIdle),
        ],
      ),
    );
  }
}
