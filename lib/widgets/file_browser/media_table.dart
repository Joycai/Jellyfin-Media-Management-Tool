import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/file_entry.dart';
import '../../models/organize_plan.dart';
import '../../services/ai_service.dart';
import '../../services/file_browser_service.dart';
import '../../services/file_label_service.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/format.dart';
import '../dialogs/preview_dialog.dart';
import '../ui/app_controls.dart';
import '../ui/glass_surface.dart';
import 'file_context_menu.dart';
import 'file_thumbnail.dart';
import 'media_columns.dart';

/// 主内容区（3.1）：工具条 + 面包屑在面板之上，文件列表面板在其下。
///
/// 骨架取值来自 02.6：左右内距 22、工具条 h36、与列表间距 12；面板本身是
/// 03.1 的 r16 玻璃卡。
class MediaTable extends StatefulWidget {
  final String searchQuery;
  final VoidCallback onOrganize;
  final VoidCallback onPickFolder;

  /// 右侧面板是否展开 —— 工具条上的开关要反映它。
  final bool panelOpen;
  final VoidCallback onTogglePanel;

  const MediaTable({
    super.key,
    required this.searchQuery,
    required this.onOrganize,
    required this.onPickFolder,
    required this.panelOpen,
    required this.onTogglePanel,
  });

  /// The rows actually rendered for [searchQuery] — the same list the
  /// select-all shortcut acts on, which is why it lives here rather than
  /// inline in [build].
  static List<FileEntry> visibleFiles(
    List<FileEntry> files,
    String searchQuery,
  ) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return files;
    return files
        .where((f) => p.basename(f.path).toLowerCase().contains(query))
        .toList();
  }

  /// Distance from the panel edge to the first column, for the header and for
  /// a row alike. Rows reach it as ListView padding 8 + row padding 10; the
  /// header applies it directly. They have to agree or the column edges the
  /// user drags stop lining up with the cells below them.
  static const contentInset = AppSpacing.sm + AppSpacing.md;

  static String localizedType(AppLocalizations l10n, String label, bool isDir) {
    if (isDir) return l10n.typeFolder;
    return switch (label) {
      'Video' => l10n.typeVideo,
      'Subtitle' => l10n.typeSubtitle,
      'Image' => l10n.typeImage,
      'Metadata' => l10n.typeMetadata,
      'Audio' => l10n.typeAudio,
      'Text' => l10n.typeText,
      _ => l10n.typeOther,
    };
  }

  @override
  State<MediaTable> createState() => _MediaTableState();
}

class _MediaTableState extends State<MediaTable> {
  /// Column weights while a divider is being dragged, or null when no drag is
  /// in flight and the persisted weights apply.
  ///
  /// A drag used to write straight through [SettingsService] on every pointer
  /// move. That notified every listener in the app — both themes rebuilt in
  /// `MyApp`, the sidebar, the AI panel — and re-armed the `config.json` save
  /// debounce, all to move one divider one pixel. Held here the drag rebuilds
  /// this table and nothing else, and the width is committed once, on release.
  final ValueNotifier<Map<MediaColumn, double>?> _dragWeights = ValueNotifier(
    null,
  );

  @override
  void dispose() {
    _dragWeights.dispose();
    super.dispose();
  }

  void _resize({
    required MediaColumn column,
    required double dx,
    required double available,
    required Map<MediaColumn, double> stored,
  }) {
    _dragWeights.value = MediaColumnLayout.resize(
      weights: _dragWeights.value ?? stored,
      column: column,
      dx: dx,
      available: available,
    );
  }

  /// Persist the width the drag landed on. Also the cancel path: the columns
  /// have already moved on screen, so dropping the value would snap them back.
  void _commitResize() {
    final weights = _dragWeights.value;
    if (weights == null) return;
    _dragWeights.value = null;
    context.read<SettingsService>().setColumnWeights(weights);
  }

  void _resetWidths() {
    _dragWeights.value = null;
    context.read<SettingsService>().resetColumnWeights();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Deliberately one narrow select per value rather than a watch per
    // service. Clicking a row notifies FileBrowserService, and watching it
    // here rebuilt the table — and with it every visible row — for a change
    // that concerns two of them. Rows now watch their own selection state
    // (see [_FileRow]), and this build runs only when the directory, its
    // contents, the plan or the column widths actually change.
    final currentDirectory = context.select<FileBrowserService, String?>(
      (b) => b.currentDirectory,
    );

    if (currentDirectory == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSizes.contentPaddingH),
        child: _DropZoneEmptyState(onPickFolder: widget.onPickFolder),
      );
    }

    final files = MediaTable.visibleFiles(
      context.select<FileBrowserService, List<FileEntry>>((b) => b.files),
      widget.searchQuery,
    );

    // Index plan actions by their folder-relative source path for quick lookup.
    final plan = context.select<AiService, OrganizePlan?>((a) => a.currentPlan);
    final base = context.select<AiService, String?>((a) => a.planBaseDir);
    final actionBySource = <String, OrganizeAction>{};
    if (plan != null && base != null) {
      for (final a in plan.actions) {
        actionBySource[a.source] = a;
      }
    }

    // Read once here rather than per row so toggling the setting doesn't
    // subscribe every visible _FileRow to SettingsService.
    final showThumbnails = context.select<SettingsService, bool>(
      (s) => s.showVideoThumbnails,
    );
    final storedWeights = context
        .select<SettingsService, Map<MediaColumn, double>>(
          (s) => s.columnWeights,
        );

    return Padding(
      padding: const EdgeInsets.all(AppSizes.contentPaddingH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppSizes.toolbar,
            child: _Toolbar(
              onOrganize: widget.onOrganize,
              onPickFolder: widget.onPickFolder,
              panelOpen: widget.panelOpen,
              onTogglePanel: widget.onTogglePanel,
            ),
          ),
          const SizedBox(height: AppSpacing.md12),
          Expanded(
            // One measurement for the whole table. Resolving widths per row
            // would let the header and the rows disagree by a rounding error,
            // which is exactly the misalignment column dragging makes obvious.
            child: LayoutBuilder(
              builder: (context, box) {
                final available =
                    box.maxWidth -
                    // The hairline border shrinks the space the panel's child
                    // actually gets — skip it and the header overflows by
                    // exactly that much.
                    2 -
                    MediaTable.contentInset * 2 -
                    MediaColumnLayout.gutter -
                    MediaColumnLayout.dividerHitWidth *
                        (MediaColumn.values.length - 1);
                // Only this subtree redraws while a divider is under the
                // pointer.
                return ValueListenableBuilder<Map<MediaColumn, double>?>(
                  valueListenable: _dragWeights,
                  builder: (context, dragged, _) => _panel(
                    context,
                    l10n: l10n,
                    files: files,
                    actionBySource: actionBySource,
                    base: base,
                    showThumbnails: showThumbnails,
                    widths: MediaColumnLayout.resolve(
                      available,
                      dragged ?? storedWeights,
                    ),
                    onResize: (column, dx) => _resize(
                      column: column,
                      dx: dx,
                      available: available,
                      stored: storedWeights,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required AppLocalizations l10n,
    required List<FileEntry> files,
    required Map<String, OrganizeAction> actionBySource,
    required String? base,
    required bool showThumbnails,
    required Map<MediaColumn, double> widths,
    required void Function(MediaColumn column, double dx) onResize,
  }) {
    final t = context.tokens;
    final browser = context.read<FileBrowserService>();
    return GlassSurface(
      // 03.1 的列表面板：white 5% + blur 40 saturate 180 + 描边 white 8%。
      fill: t.cardFill,
      blur: t.blurPanel,
      saturate: true,
      borderRadius: BorderRadius.circular(AppRadii.panel + 2),
      border: Border.all(color: t.stroke),
      shadow: t.elevation.card,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MediaTable.contentInset,
            ),
            child: AppColumnHeader(
              // Vertical only: the horizontal inset is the Padding above, and
              // it has to be exactly the rows' own (ListView 8 + row 10) or
              // the header labels stop sitting over their columns.
              padding: const EdgeInsets.fromLTRB(
                0,
                AppSpacing.md12,
                0,
                AppSpacing.sm,
              ),
              children: [
                _HeaderRow(
                  l10n: l10n,
                  widths: widths,
                  onResize: onResize,
                  onResizeEnd: _commitResize,
                  onReset: _resetWidths,
                ),
              ],
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Text(
                      l10n.folderEmpty,
                      style: AppTypeScale.body.copyWith(color: t.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.xs,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final file = files[i];
                      final rel = base != null
                          ? p.relative(file.path, from: base)
                          : null;
                      return _FileRow(
                        key: ValueKey(file.path),
                        entry: file,
                        widths: widths,
                        showThumbnail: showThumbnails,
                        action: rel != null ? actionBySource[rel] : null,
                        relativeDir: rel == null
                            ? null
                            : p.dirname(rel) == '.'
                            ? null
                            : p.dirname(rel),
                        onCheck: () => browser.toggleSelection(file),
                        onTap: () {
                          final keys =
                              HardwareKeyboard.instance.logicalKeysPressed;
                          final shift =
                              keys.contains(LogicalKeyboardKey.shiftLeft) ||
                              keys.contains(LogicalKeyboardKey.shiftRight);
                          final ctrlOrCmd =
                              keys.contains(LogicalKeyboardKey.controlLeft) ||
                              keys.contains(LogicalKeyboardKey.controlRight) ||
                              keys.contains(LogicalKeyboardKey.metaLeft) ||
                              keys.contains(LogicalKeyboardKey.metaRight);
                          if (shift) {
                            browser.selectRange(files, file);
                          } else if (ctrlOrCmd) {
                            browser.toggleSelection(file);
                          } else {
                            browser.selectSingle(file);
                          }
                        },
                        onDoubleTap: () {
                          if (file.isDirectory) {
                            browser.setCurrentDirectory(file.path);
                            context.read<SettingsService>().pushRecent(
                              file.path,
                            );
                          } else if (PreviewDialog.canPreview(file)) {
                            PreviewDialog.show(context, file);
                          }
                        },
                      );
                    },
                  ),
          ),
          _FooterBar(fileCount: files.length),
        ],
      ),
    );
  }
}

/// 工具条：面包屑 + 右侧动作（3.1）。
class _Toolbar extends StatelessWidget {
  final VoidCallback onOrganize;
  final VoidCallback onPickFolder;
  final bool panelOpen;
  final VoidCallback onTogglePanel;

  const _Toolbar({
    required this.onOrganize,
    required this.onPickFolder,
    required this.panelOpen,
    required this.onTogglePanel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    // Two booleans, not the whole service. AiService also notifies on
    // connection status, usage totals and every plan change, and this bar
    // draws none of them -- it only needs to know whether the organize button
    // is live and whether to spin.
    final (isAnalyzing, canOrganize) = context.select<AiService, (bool, bool)>(
      (a) => (a.isAnalyzing, a.isConfigured && a.config.supportsTools != false),
    );
    final selectionCount = context.select<FileBrowserService, int>(
      (b) => b.selectionCount,
    );

    return Row(
      children: [
        AppIconButton(
          icon: Icons.folder_open_outlined,
          tooltip: l10n.openFolder,
          size: AppSizes.controlSm,
          onPressed: onPickFolder,
        ),
        const SizedBox(width: AppSpacing.xxs),
        AppIconButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: l10n.parentFolder,
          size: AppSizes.controlSm,
          onPressed: () => context.read<FileBrowserService>().goToParent(),
        ),
        const SizedBox(width: AppSpacing.md),
        const Expanded(child: _Breadcrumb()),
        const SizedBox(width: AppSpacing.md),
        Builder(
          builder: (context) {
            final dir = context.read<FileBrowserService>().currentDirectory;
            // Just this one bool: watching the whole service redrew the star
            // on every recent-folder push and every column commit.
            final pinned = context.select<SettingsService, bool>(
              (s) => dir != null && s.isFavorite(dir),
            );
            return AppIconButton(
              icon: pinned ? Icons.star_rounded : Icons.star_outline_rounded,
              tooltip: l10n.favorites,
              size: AppSizes.controlSm,
              active: pinned,
              onPressed: dir == null
                  ? null
                  : () => context.read<SettingsService>().toggleFavorite(dir),
            );
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        AppIconButton(
          icon: panelOpen
              ? Icons.vertical_split_rounded
              : Icons.view_sidebar_outlined,
          tooltip: l10n.togglePanel,
          size: AppSizes.controlSm,
          active: panelOpen,
          onPressed: onTogglePanel,
        ),
        const SizedBox(width: AppSpacing.sm),
        // A model known not to call tools cannot organize (there is no
        // single-shot fallback); one never checked is probed on first run.
        if (isAnalyzing)
          Container(
            height: AppSizes.control,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: t.accentDisabled,
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.badgeText,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  l10n.analyzing,
                  style: AppTypeScale.controlStrong.copyWith(
                    color: t.badgeText.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          )
        else
          AppButton.primary(
            label: selectionCount > 0
                ? l10n.organizeSelectedWithAi(selectionCount)
                : l10n.organizeWithAi,
            icon: Icons.auto_awesome,
            onPressed: canOrganize ? onOrganize : null,
          ),
      ],
    );
  }
}

/// 面包屑：mono 12，非当前段 45–50%，分隔符 `›`，当前段 90% / 500。
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb();

  @override
  Widget build(BuildContext context) {
    // Only the path is drawn here. Watching the whole service rebuilt the
    // breadcrumb -- a p.split plus a widget per segment -- on every row click
    // and every selection change, none of which move it.
    final current = context.select<FileBrowserService, String?>(
      (b) => b.currentDirectory,
    );
    final t = context.tokens;
    final dir = current!;
    final parts = p.split(dir);

    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final segment = parts[i];
      if (segment == p.separator) continue;
      final target = p.joinAll(parts.sublist(0, i + 1));
      final isLast = i == parts.length - 1;
      if (children.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '›',
              style: AppTypeScale.monoSmall.copyWith(
                color: t.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ),
        );
      }
      children.add(
        _CrumbSegment(
          label: segment.isEmpty ? p.separator : segment,
          isLast: isLast,
          onTap: isLast
              ? null
              : () {
                  context.read<FileBrowserService>().setCurrentDirectory(
                    target,
                  );
                  context.read<SettingsService>().pushRecent(target);
                },
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: children),
    );
  }
}

class _CrumbSegment extends StatelessWidget {
  final String label;
  final bool isLast;
  final VoidCallback? onTap;

  const _CrumbSegment({required this.label, required this.isLast, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: 2,
          ),
          child: Text(
            label,
            style: AppTypeScale.monoSmall.copyWith(
              fontSize: AppTypeScale.sizeCaption,
              fontWeight: isLast ? FontWeight.w500 : FontWeight.w400,
              color: isLast ? t.textTitle : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final AppLocalizations l10n;
  final Map<MediaColumn, double> widths;
  final void Function(MediaColumn column, double dx) onResize;

  /// Fired when the pointer is released, so the drag can be persisted once
  /// instead of on every move.
  final VoidCallback onResizeEnd;
  final VoidCallback onReset;

  const _HeaderRow({
    required this.l10n,
    required this.widths,
    required this.onResize,
    required this.onResizeEnd,
    required this.onReset,
  });

  String _label(MediaColumn column) => switch (column) {
    MediaColumn.name => l10n.colName,
    MediaColumn.type => l10n.colType,
    MediaColumn.size => l10n.colSize,
    MediaColumn.suggestion => l10n.colAiSuggestion,
    MediaColumn.confidence => l10n.colConfidence,
  };

  @override
  Widget build(BuildContext context) {
    final columns = MediaColumn.values;
    return Expanded(
      child: Row(
        children: [
          // Aligns with the row checkbox column.
          const SizedBox(width: MediaColumnLayout.gutter),
          for (var i = 0; i < columns.length; i++) ...[
            SizedBox(
              width: widths[columns[i]],
              child: Text(
                _label(columns[i]).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: columns[i] == MediaColumn.confidence
                    ? TextAlign.right
                    : TextAlign.start,
              ),
            ),
            // No divider after the last column: there is nothing on its right
            // to trade width with.
            if (i < columns.length - 1)
              _ColumnDivider(
                onDrag: (dx) => onResize(columns[i], dx),
                onDragEnd: onResizeEnd,
                onReset: onReset,
                tooltip: l10n.colResetWidths,
              ),
          ],
        ],
      ),
    );
  }
}

/// The draggable edge between two columns.
///
/// Drawn as a hairline but grabbed over [MediaColumnLayout.dividerHitWidth],
/// because a one-pixel target is a test of aim rather than a control. Double
/// click restores the defaults, which is the usual escape hatch once someone
/// has dragged a column down to nothing.
class _ColumnDivider extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;
  final String tooltip;

  const _ColumnDivider({
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
    required this.tooltip,
  });

  @override
  State<_ColumnDivider> createState() => _ColumnDividerState();
}

class _ColumnDividerState extends State<_ColumnDivider> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onDoubleTap: widget.onReset,
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: AppMotion.progress,
          child: SizedBox(
            width: MediaColumnLayout.dividerHitWidth,
            height: 14,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.respecting(context, AppMotion.overlayIn),
                width: active ? 2 : 1,
                height: active ? 14 : 9,
                decoration: BoxDecoration(
                  color: active ? t.accent : t.stroke,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final FileEntry entry;
  final Map<MediaColumn, double> widths;
  final OrganizeAction? action;
  final bool showThumbnail;

  /// 名称列副行：相对目录（3.1 的「/未整理/Dune2/」）。
  final String? relativeDir;
  final VoidCallback onCheck;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _FileRow({
    super.key,
    required this.entry,
    required this.widths,
    required this.action,
    required this.showThumbnail,
    required this.relativeDir,
    required this.onCheck,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  /// Manual double-click detection. Registering both `onTap` and
  /// `onDoubleTap` on the row makes the gesture arena hold every single tap
  /// for the ~300ms double-tap window before firing it, which made selection
  /// feel laggy. With only `onTap` registered, taps fire immediately; a second
  /// tap within [_doubleClickWindow] is treated as the double-click (the first
  /// tap having already selected the row is the standard file-manager
  /// behavior and harmless).
  DateTime? _lastTapAt;
  static const _doubleClickWindow = AppMotion.progress;

  FileEntry get entry => widget.entry;
  OrganizeAction? get action => widget.action;

  void _handleTap() {
    final now = DateTime.now();
    final isDoubleClick =
        _lastTapAt != null && now.difference(_lastTapAt!) < _doubleClickWindow;
    _lastTapAt = isDoubleClick ? null : now;
    if (isDoubleClick) {
      widget.onDoubleTap();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    final isDir = entry.isDirectory;
    final label = FileLabelService.getLabel(entry.extension);
    final iconColor = FileLabelService.getIconColor(
      isDir ? 'Folder' : label,
      isDir,
    );
    final name = entry.name;
    final size = isDir ? '—' : formatBytes(entry.size);

    // Each row subscribes to its own selection state. Computed in the parent's
    // itemBuilder instead, as it was, one click rebuilt every visible row to
    // change the appearance of two.
    final path = entry.path;
    final selected = context.select<FileBrowserService, bool>(
      (b) => b.selectedFile?.path == path,
    );
    final checked = context.select<FileBrowserService, bool>(
      (b) => b.isSelected(path),
    );
    final needsReview = action?.status == ActionStatus.needsReview;
    final showCheckbox = _hovered || checked;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AppListRow(
        height: AppSizes.rowTall,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        selected: selected,
        checked: checked && !selected,
        onTap: _handleTap,
        onSecondaryTap: (pos) =>
            showFileContextMenu(context, globalPosition: pos, entry: entry),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Row(
            children: [
              SizedBox(
                width: MediaColumnLayout.gutter,
                child: AnimatedOpacity(
                  opacity: showCheckbox ? 1.0 : 0.0,
                  duration: AppMotion.respecting(context, AppMotion.overlayOut),
                  curve: AppMotion.standard,
                  child: IgnorePointer(
                    ignoring: !showCheckbox,
                    child: Checkbox(
                      value: checked,
                      onChanged: (_) => widget.onCheck(),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: widget.widths[MediaColumn.name],
                child: Row(
                  children: [
                    FileThumbnail(
                      entry: entry,
                      label: label,
                      iconColor: iconColor,
                      enabled: widget.showThumbnail,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.md12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: name,
                            waitDuration: AppMotion.progress,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.body.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: t.textTitle,
                              ),
                            ),
                          ),
                          if (needsReview)
                            Text(
                              '⚠ ${l10n.needsReview}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.caption.copyWith(
                                fontSize: AppTypeScale.sizeMono,
                                color: t.warningText,
                              ),
                            )
                          else if (widget.relativeDir != null)
                            Text(
                              widget.relativeDir!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.monoSmall.copyWith(
                                color: t.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Each cell mirrors the header's gap so the two stay in step;
              // the gap is where the header's drag handle sits.
              const SizedBox(width: MediaColumnLayout.dividerHitWidth),
              SizedBox(
                width: widget.widths[MediaColumn.type],
                child: Text(
                  MediaTable.localizedType(l10n, label, isDir),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.caption.copyWith(
                    fontSize: AppTypeScale.sizeCaption,
                    color: t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: MediaColumnLayout.dividerHitWidth),
              SizedBox(
                width: widget.widths[MediaColumn.size],
                child: Text(
                  size,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.monoSmall.copyWith(
                    fontSize: AppTypeScale.sizeCaption,
                    color: t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: MediaColumnLayout.dividerHitWidth),
              SizedBox(
                width: widget.widths[MediaColumn.suggestion],
                child: _SuggestionCell(action: action),
              ),
              const SizedBox(width: MediaColumnLayout.dividerHitWidth),
              SizedBox(
                width: widget.widths[MediaColumn.confidence],
                child: _ConfidenceCell(action: action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCell extends StatelessWidget {
  final OrganizeAction? action;
  const _SuggestionCell({required this.action});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (action == null) {
      return Text('—', style: TextStyle(color: t.textDisabled));
    }
    final applied = action!.status == ActionStatus.applied;
    final review = action!.status == ActionStatus.needsReview;
    final color = applied
        ? t.successText
        : review
        ? t.warningText
        : (t.isDark ? AppPalette.accentOnDarkSoft : t.accentInk);
    return Row(
      children: [
        Icon(
          applied
              ? Icons.check_circle_rounded
              : Icons.subdirectory_arrow_right_rounded,
          size: 13,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Tooltip(
            message: action!.target,
            waitDuration: AppMotion.progress,
            child: Text(
              action!.target,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.caption.copyWith(
                fontSize: AppTypeScale.sizeCaption,
                color: color,
                height: 1.25,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 置信度：46×5 · r3 进度条 + mono 百分比，右对齐。
class _ConfidenceCell extends StatelessWidget {
  final OrganizeAction? action;
  const _ConfidenceCell({required this.action});

  @override
  Widget build(BuildContext context) {
    if (action == null) return const SizedBox.shrink();
    final t = context.tokens;
    final v = action!.confidence.clamp(0.0, 1.0);
    // 高置信走青→蓝渐变，低置信走橙→黄；文字取渐变的起点色（3.1）。
    final high = v >= 0.6;
    final gradient = high
        ? [t.success, t.accent]
        : [const Color(0xFFFF9A6C), const Color(0xFFFFD166)];
    final textColor = high ? t.successText : t.warningText;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible so the bar gives way first: the cell's fixed parts alone
        // (spacing + percentage) already approach the column's minimum width,
        // and a rigid bar overflows as soon as the column is dragged narrow.
        Flexible(
          child: SizedBox(
            width: 46,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: Container(
                height: 5,
                color: t.strokeStrong,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: v),
                  duration: AppMotion.respecting(context, AppMotion.progress),
                  curve: Curves.linear,
                  builder: (context, value, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradient),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 32,
          child: Text(
            '${(v * 100).round()}%',
            textAlign: TextAlign.right,
            style: AppTypeScale.monoSmall.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// 面板底部状态条（3.1）：左计数与总大小，右语义圆点 + 状态文案。
class _FooterBar extends StatelessWidget {
  final int fileCount;
  const _FooterBar({required this.fileCount});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    // The footer draws four values off two services. Watching either service
    // whole rebuilt it on every row click, every file-list reload, and every
    // AI status or usage notification -- which is the same trap the rest of
    // this file documents avoiding.
    final (selectionCount, hasFocus, dir) = context
        .select<FileBrowserService, (int, bool, String?)>(
          (b) => (b.selectionCount, b.selectedFile != null, b.currentDirectory),
        );
    final (isAnalyzing, analyzedHere) = context.select<AiService, (bool, bool)>(
      (a) => (a.isAnalyzing, a.currentPlan != null && a.planBaseDir == dir),
    );

    final String statusText;
    final Color statusColor;
    if (isAnalyzing) {
      statusText = l10n.analyzing;
      statusColor = t.accent;
    } else if (analyzedHere) {
      statusText = l10n.analysisComplete;
      statusColor = t.success;
    } else {
      statusText = l10n.notAnalyzed;
      statusColor = t.textMuted;
    }

    final selCount = selectionCount > 0 ? selectionCount : (hasFocus ? 1 : 0);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaTable.contentInset,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.stroke)),
      ),
      child: DefaultTextStyle(
        style: AppTypeScale.caption.copyWith(color: t.textSecondary),
        child: Row(
          children: [
            Text(
              selCount > 0
                  ? '${l10n.selectedCount(selCount)} · ${l10n.itemsCount(fileCount)}'
                  : l10n.itemsCount(fileCount),
            ),
            if (selectionCount > 0) ...[
              const SizedBox(width: AppSpacing.md),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      context.read<FileBrowserService>().clearSelection(),
                  child: Text(
                    l10n.clearSelection,
                    style: AppTypeScale.caption.copyWith(color: t.accentText),
                  ),
                ),
              ),
            ],
            const Spacer(),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(statusText),
          ],
        ),
      ),
    );
  }
}

/// 3.3 拖入空状态：680 × 340 的虚线框、悬浮文件夹图标、两个入口。
///
/// 「连接 NAS」在设计稿里存在，应用没有这个能力 —— 按占位方式画出来但禁用，
/// 能力本身进 backlog。半个按钮比没有按钮更能说明「这里以后会有」。
class _DropZoneEmptyState extends StatelessWidget {
  final VoidCallback onPickFolder;
  const _DropZoneEmptyState({required this.onPickFolder});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    return Center(
      child: SizedBox(
        width: 680,
        height: 340,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: t.accent.withValues(alpha: 0.55),
            radius: 20,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.panel),
              gradient: RadialGradient(
                colors: [
                  t.accent.withValues(alpha: 0.15),
                  t.accent.withValues(alpha: 0),
                ],
                radius: 0.7,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FolderGlyph(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  l10n.dropFoldersTitle,
                  style: const TextStyle(
                    fontSize: AppTypeScale.sizeHeading,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.24,
                  ).copyWith(color: t.textTitle),
                ),
                const SizedBox(height: AppSpacing.md12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    l10n.dropFoldersHint,
                    textAlign: TextAlign.center,
                    style: AppTypeScale.body.copyWith(
                      color: t.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 60, height: 1, color: t.strokeStrong),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        l10n.orSeparator,
                        style: AppTypeScale.caption.copyWith(
                          color: t.textMuted,
                        ),
                      ),
                    ),
                    Container(width: 60, height: 1, color: t.strokeStrong),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppButton(
                      label: l10n.openFolder,
                      icon: Icons.folder_open_outlined,
                      height: 34,
                      onPressed: onPickFolder,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton(
                      label: l10n.connectNas,
                      icon: Icons.lan_outlined,
                      height: 34,
                      tooltip: l10n.comingSoon,
                      // 占位：能力未实现，禁用而不是假装可点。
                      onPressed: null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 100 × 80 的文件夹字形：下层主体 + 上层书签 + 中间下箭头。
class _FolderGlyph extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 100,
      height: 80,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 8,
            child: Container(
              width: 46,
              height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent.withValues(alpha: 0.5),
                    t.ai.withValues(alpha: 0.4),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 14,
            child: Container(
              width: 100,
              height: 66,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent.withValues(alpha: 0.4),
                    t.ai.withValues(alpha: 0.3),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: t.reduceEffects
                    ? null
                    : [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.4),
                          blurRadius: 40,
                          offset: const Offset(0, 12),
                        ),
                      ],
              ),
            ),
          ),
          const Positioned.fill(
            child: Center(
              child: Icon(
                Icons.arrow_downward_rounded,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `border: 2px dashed` —— Flutter 的 `Border` 只画实线。
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    const dash = 8.0;
    const gap = 6.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
