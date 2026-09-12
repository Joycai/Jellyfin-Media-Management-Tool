import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/history_service.dart';
import '../../services/settings_service.dart';
import '../../services/thumbnail_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/format.dart';
import '../ui/app_controls.dart';
import 'settings_controls.dart';

/// 6.2 · 隐私与缓存（设计稿画板 22）。
///
/// 设计稿的缓存分了「元数据缓存 / 图片缓存 / 运行日志」三档，那是它设想的应用。
/// 这里按**实际落在磁盘上的三样东西**分：缩略图、撤销备份、整理记忆 —— 一张列出
/// 三个不存在目录的缓存表，比没有这张表更糟。
///
/// 撤销备份那一行没有「清理」：它装的是撤销时用来还原被覆盖文件的真副本，删掉就
/// 等于把还没过期的撤销记录变成空头支票。[HistoryService] 已经按 7 天自动清理，
/// 这里只报大小。
class PrivacySection extends StatefulWidget {
  const PrivacySection({super.key});

  @override
  State<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<PrivacySection> {
  _CacheSizes? _sizes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final sizes = await _CacheSizes.measure();
    if (!mounted) return;
    setState(() => _sizes = sizes);
  }

  Future<void> _clearThumbnails() async {
    await ThumbnailService.instance.clearCache();
    await _measure();
  }

  Future<void> _clearAgent() async {
    final dir = await _CacheSizes._agentDir();
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // 记忆是纯缓存：删不掉就下次再说，没必要为此打断设置页。
      }
    }
    await _measure();
  }

  Future<void> _clearAll() async {
    await _clearThumbnails();
    await _clearAgent();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sizes = _sizes;
    return SettingsPage(
      children: [
        SettingsColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionTitle(l10n.privacyLocations),
              const _LocationsCard(),
              const SizedBox(height: AppSpacing.xl),
              SettingsSectionTitle(
                l10n.privacyCaches,
                trailing: SettingsMiniButton(
                  l10n.privacyClearAll,
                  onPressed: sizes == null || sizes.clearable == 0
                      ? null
                      : _clearAll,
                ),
              ),
              _CachesCard(
                sizes: sizes,
                onClearThumbnails: _clearThumbnails,
                onClearAgent: _clearAgent,
              ),
              SettingsFootnote(l10n.privacyCacheNote),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionTitle(
                l10n.privacySection,
                trailing: SettingsSoonTag(l10n.comingSoon),
              ),
              const _PrivacyToggles(),
              const SizedBox(height: AppSpacing.xl),
              SettingsSectionTitle(
                l10n.privacyDanger,
                trailing: SettingsSoonTag(l10n.comingSoon),
              ),
              const _DangerZone(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 配置与数据位置 ──────────────────────────────────────────────────────────

class _LocationsCard extends StatelessWidget {
  const _LocationsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final path = settings.configPath;
    return SettingsRowsCard(
      children: [
        SettingsRow(
          leading: const SettingsRowIcon(Icons.folder_outlined),
          title: l10n.privacyConfigFolder,
          subtitle: path ?? '—',
          trailing: [
            SettingsMiniButton(
              l10n.privacyBrowse,
              onPressed: settings.openConfigFolder,
            ),
            SettingsMiniButton(
              l10n.privacyCopyPath,
              onPressed: path == null
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: path));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.privacyCopied)),
                      );
                    },
            ),
          ],
        ),
        SettingsRow(
          leading: const SettingsRowIcon(Icons.description_outlined),
          title: l10n.privacyDataFiles,
          subtitle: l10n.privacyDataFilesValue,
          subtitleMono: false,
        ),
      ],
    );
  }
}

// ── 缓存 ────────────────────────────────────────────────────────────────────

class _CachesCard extends StatelessWidget {
  final _CacheSizes? sizes;
  final VoidCallback onClearThumbnails;
  final VoidCallback onClearAgent;

  const _CachesCard({
    required this.sizes,
    required this.onClearThumbnails,
    required this.onClearAgent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final history = context.watch<HistoryService>();

    String size(int? bytes) =>
        bytes == null ? '—' : formatBytes(bytes, zero: '0 B');

    Widget value(int? bytes) => Text(
      size(bytes),
      style: AppTypeScale.monoSmall.copyWith(color: t.textBody),
    );

    return SettingsRowsCard(
      children: [
        SettingsRow(
          title: l10n.privacyCacheThumbnails,
          subtitle: l10n.privacyCacheThumbnailsHint,
          subtitleMono: false,
          trailing: [
            value(sizes?.thumbnails),
            SettingsMiniButton(
              l10n.privacyClear,
              onPressed: (sizes?.thumbnails ?? 0) == 0
                  ? null
                  : onClearThumbnails,
            ),
          ],
        ),
        SettingsRow(
          title: l10n.privacyCacheUndo,
          // gen_l10n 按占位符名字的字母序排参数，不是按它们在文案里的出现顺序：
          // 这里是 (count, days)。
          subtitle: l10n.privacyCacheUndoHint(
            history.entries.length,
            HistoryService.retentionDays,
          ),
          subtitleMono: false,
          trailing: [value(sizes?.undoBlobs)],
        ),
        SettingsRow(
          title: l10n.privacyCacheAgent,
          subtitle: l10n.privacyCacheAgentHint,
          subtitleMono: false,
          trailing: [
            value(sizes?.agent),
            SettingsMiniButton(
              l10n.privacyClear,
              onPressed: (sizes?.agent ?? 0) == 0 ? null : onClearAgent,
            ),
          ],
        ),
        SettingsRow(
          title: l10n.privacyTotal,
          trailing: [
            Text(
              size(sizes?.total),
              style: AppTypeScale.monoBody.copyWith(
                color: t.textTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 三处缓存的大小，一次量完。
class _CacheSizes {
  final int thumbnails;
  final int undoBlobs;
  final int agent;

  const _CacheSizes({
    required this.thumbnails,
    required this.undoBlobs,
    required this.agent,
  });

  int get total => thumbnails + undoBlobs + agent;

  /// 「全部清理」实际能回收的部分 —— 撤销备份不在其中。
  int get clearable => thumbnails + agent;

  static Future<Directory> _agentDir() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'agent'));

  static const empty = _CacheSizes(thumbnails: 0, undoBlobs: 0, agent: 0);

  /// 量不出来就报零，整页照常显示。这是三个诊断数字，不值得为它们让设置页出错
  /// —— 在没有 path_provider 的 widget 测试里，它本来就量不出来。
  static Future<_CacheSizes> measure() async {
    try {
      final support = await getApplicationSupportDirectory();
      return _CacheSizes(
        thumbnails: await ThumbnailService.instance.cacheSizeOnDisk(),
        undoBlobs: await _dirSize(
          Directory(p.join(support.path, 'undo', 'blobs')),
        ),
        agent: await _dirSize(Directory(p.join(support.path, 'agent'))),
      );
    } catch (_) {
      return empty;
    }
  }

  /// 递归求和。任何一步失败都当作 0：这是个诊断数字，不该把设置页拖垮。
  static Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on FileSystemException {
            continue;
          }
        }
      }
    } on FileSystemException {
      return total;
    }
    return total;
  }
}

// ── 隐私开关（全部占位：本应用不收集任何遥测） ──────────────────────────────

class _PrivacyToggles extends StatelessWidget {
  const _PrivacyToggles();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPlaceholder(
          child: SettingsRowsCard(
            children: [
              SettingsToggleRow(
                label: l10n.privacyTelemetry,
                subtitle: l10n.privacyTelemetryHint,
                value: false,
              ),
              SettingsToggleRow(
                label: l10n.privacyCrashReports,
                subtitle: l10n.privacyCrashReportsHint,
                value: false,
              ),
              SettingsToggleRow(
                label: l10n.privacyLogAiBodies,
                subtitle: l10n.privacyLogAiBodiesHint,
                value: false,
              ),
              SettingsToggleRow(
                label: l10n.privacyClearTempOnExit,
                value: false,
              ),
            ],
          ),
        ),
        SettingsFootnote(l10n.privacyNoTelemetry),
      ],
    );
  }
}

// ── 危险操作 ────────────────────────────────────────────────────────────────

class _DangerZone extends StatelessWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPlaceholder(
          child: SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.privacyReset,
                        style: AppTypeScale.controlStrong.copyWith(
                          color: t.dangerText,
                        ),
                      ),
                    ),
                    AppButton(
                      label: l10n.privacyResetAction,
                      kind: AppButtonKind.danger,
                      height: AppSizes.controlSm,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.privacyResetBody,
                  style: AppTypeScale.caption.copyWith(
                    color: t.textMuted,
                    height: AppTypeScale.leadingBody,
                  ),
                ),
              ],
            ),
          ),
        ),
        SettingsFootnote(l10n.privacyResetPlaceholder),
      ],
    );
  }
}
