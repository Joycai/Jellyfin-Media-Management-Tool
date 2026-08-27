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
import '../../utils/format.dart';
import '../dialogs/preview_dialog.dart';
import '../glass/glass_panel.dart';
import 'file_context_menu.dart';
import 'file_thumbnail.dart';
import 'media_columns.dart';

/// Center pane: breadcrumb + actions, the file table with AI-suggestion and
/// confidence columns, and a status footer.
class MediaTable extends StatefulWidget {
  final String searchQuery;
  final VoidCallback onOrganize;
  final VoidCallback onPickFolder;

  const MediaTable({
    super.key,
    required this.searchQuery,
    required this.onOrganize,
    required this.onPickFolder,
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
  /// a row alike. Rows reach it as ListView padding 12 + row margin 8 + row
  /// padding 14; the header applies it directly. They have to agree or the
  /// column edges the user drags stop lining up with the cells below them.
  static const contentInset = 34.0;

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
      return GlassPanel(
        radius: 24,
        elevated: true,
        child: _EmptyState(onPickFolder: widget.onPickFolder),
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

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // One measurement for the whole table. Resolving widths per row would let
    // the header and the rows disagree by a rounding error, which is exactly
    // the misalignment column dragging makes obvious.
    return LayoutBuilder(
      builder: (context, box) {
        final available =
            box.maxWidth -
            // The measurement happens outside the GlassPanel, whose hairline
            // border shrinks the space its child actually gets — skip it and
            // the header overflows by exactly that much.
            GlassPanel.borderWidth * 2 -
            MediaTable.contentInset * 2 -
            MediaColumnLayout.gutter -
            MediaColumnLayout.dividerHitWidth * (MediaColumn.values.length - 1);
        // Only this subtree redraws while a divider is under the pointer.
        return ValueListenableBuilder<Map<MediaColumn, double>?>(
          valueListenable: _dragWeights,
          builder: (context, dragged, _) {
            return _table(
              context,
              l10n: l10n,
              files: files,
              actionBySource: actionBySource,
              base: base,
              showThumbnails: showThumbnails,
              scheme: scheme,
              isDark: isDark,
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
            );
          },
        );
      },
    );
  }

  Widget _table(
    BuildContext context, {
    required AppLocalizations l10n,
    required List<FileEntry> files,
    required Map<String, OrganizeAction> actionBySource,
    required String? base,
    required bool showThumbnails,
    required ColorScheme scheme,
    required bool isDark,
    required Map<MediaColumn, double> widths,
    required void Function(MediaColumn column, double dx) onResize,
  }) {
    final browser = context.read<FileBrowserService>();
    return GlassPanel(
      radius: 24,
      elevated: true,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                scheme.primary.withValues(alpha: 0.22),
                scheme.primary.withValues(alpha: 0.08),
                scheme.secondary.withValues(alpha: 0.18),
              ]
            // Opaque so the card stays crisp white (no backdrop bleed at the
            // edges) with just a faint blue→mint tint.
            : const [Color(0xFFEFF3FE), Color(0xFFFFFFFF), Color(0xFFEFF7F3)],
        stops: const [0.0, 0.5, 1.0],
      ),
      child: Column(
        children: [
          _TopBar(
            onOrganize: widget.onOrganize,
            onPickFolder: widget.onPickFolder,
          ),
          const _Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MediaTable.contentInset,
              12,
              MediaTable.contentInset,
              6,
            ),
            child: _HeaderRow(
              l10n: l10n,
              widths: widths,
              onResize: onResize,
              onResizeEnd: _commitResize,
              onReset: _resetWidths,
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Text(
                      l10n.folderEmpty,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
          const _Divider(),
          _FooterBar(fileCount: files.length),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onOrganize;
  final VoidCallback onPickFolder;
  const _TopBar({required this.onOrganize, required this.onPickFolder});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ai = context.watch<AiService>();
    final selectionCount = context.select<FileBrowserService, int>(
      (b) => b.selectionCount,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      child: Row(
        children: [
          Expanded(child: _Breadcrumb(onPickFolder: onPickFolder)),
          const SizedBox(width: 4),
          Builder(
            builder: (context) {
              final dir = context.read<FileBrowserService>().currentDirectory;
              // Just this one bool: watching the whole service redrew the star
              // on every recent-folder push and every column commit.
              final pinned = context.select<SettingsService, bool>(
                (s) => dir != null && s.isFavorite(dir),
              );
              return IconButton(
                tooltip: l10n.favorites,
                onPressed: dir == null
                    ? null
                    : () => context.read<SettingsService>().toggleFavorite(dir),
                icon: Icon(
                  pinned ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: pinned ? const Color(0xFFFFB020) : null,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: ai.isAnalyzing || !ai.isConfigured ? null : onOrganize,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: ai.isAnalyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(
              selectionCount > 0
                  ? l10n.organizeSelectedWithAi(selectionCount)
                  : l10n.organizeWithAi,
            ),
          ),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final VoidCallback onPickFolder;
  const _Breadcrumb({required this.onPickFolder});

  @override
  Widget build(BuildContext context) {
    final browser = context.watch<FileBrowserService>();
    final scheme = Theme.of(context).colorScheme;
    final dir = browser.currentDirectory!;
    final parts = p.split(dir);

    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final segment = parts[i];
      if (segment == p.separator) continue;
      final target = p.joinAll(parts.sublist(0, i + 1));
      final isLast = i == parts.length - 1;
      if (children.isNotEmpty) {
        children.add(
          Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
        );
      }
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: isLast
              ? null
              : () {
                  browser.setCurrentDirectory(target);
                  context.read<SettingsService>().pushRecent(target);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              segment.isEmpty ? p.separator : segment,
              style: TextStyle(
                fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                color: isLast ? scheme.onSurface : scheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        IconButton(
          tooltip: AppLocalizations.of(context)!.openFolder,
          onPressed: onPickFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 20),
        ),
        if (browser.currentDirectory != null)
          IconButton(
            tooltip: AppLocalizations.of(context)!.parentFolder,
            onPressed: browser.goToParent,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: children),
          ),
        ),
      ],
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
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final columns = MediaColumn.values;

    return Row(
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
              style: style,
              textAlign: columns[i] == MediaColumn.confidence
                  ? TextAlign.right
                  : TextAlign.start,
            ),
          ),
          // No divider after the last column: there is nothing on its right to
          // trade width with.
          if (i < columns.length - 1)
            _ColumnDivider(
              onDrag: (dx) => onResize(columns[i], dx),
              onDragEnd: onResizeEnd,
              onReset: onReset,
              tooltip: l10n.colResetWidths,
            ),
        ],
      ],
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
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        // Cancel commits too: the columns have already moved on screen, so
        // dropping the pending width would snap them back under the pointer.
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
          waitDuration: const Duration(milliseconds: 900),
          child: SizedBox(
            width: MediaColumnLayout.dividerHitWidth,
            height: 18,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: active ? 2 : 1,
                height: active ? 16 : 10,
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(1),
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
  final VoidCallback onCheck;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _FileRow({
    super.key,
    required this.entry,
    required this.widths,
    required this.action,
    required this.showThumbnail,
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
  /// `onDoubleTap` on the InkWell makes the gesture arena hold every single
  /// tap for the ~300ms double-tap window before firing it, which made
  /// selection feel laggy. With only `onTap` registered, taps fire
  /// immediately; a second tap within [_doubleClickWindow] is treated as the
  /// double-click (the first tap having already selected the row is the
  /// standard file-manager behavior and harmless).
  DateTime? _lastTapAt;
  static const _doubleClickWindow = Duration(milliseconds: 300);

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
    final scheme = Theme.of(context).colorScheme;
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
    final highlighted = selected || checked;
    final showCheckbox = _hovered || checked;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      // Context menu: right-click (desktop) or long-press (touch). Lives
      // outside the InkWell so it doesn't interfere with tap latency.
      child: GestureDetector(
        onSecondaryTapDown: (d) => showFileContextMenu(
          context,
          globalPosition: d.globalPosition,
          entry: entry,
        ),
        onLongPressStart: (d) => showFileContextMenu(
          context,
          globalPosition: d.globalPosition,
          entry: entry,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: highlighted
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.32),
                      scheme.primary.withValues(alpha: 0.20),
                    ],
                  )
                : null,
            border: highlighted
                ? Border.all(
                    color: scheme.primary.withValues(alpha: 0.55),
                    width: 1,
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              // Single onTap only — see _handleTap for why onDoubleTap is not
              // registered here.
              onTap: _handleTap,
              onHover: (h) => setState(() => _hovered = h),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaColumnLayout.gutter,
                      child: AnimatedOpacity(
                        opacity: showCheckbox ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.ease,
                        child: IgnorePointer(
                          ignoring: !showCheckbox,
                          child: Checkbox(
                            value: checked,
                            onChanged: (_) => widget.onCheck(),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
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
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: name,
                                  waitDuration: const Duration(
                                    milliseconds: 350,
                                  ),
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (action?.status == ActionStatus.needsReview)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 13,
                                          color: Colors.orange.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          l10n.needsReview,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Each cell mirrors the header's gap so the two stay in
                    // step; the gap is where the header's drag handle sits.
                    const SizedBox(width: MediaColumnLayout.dividerHitWidth),
                    SizedBox(
                      width: widget.widths[MediaColumn.type],
                      child: Text(
                        MediaTable.localizedType(l10n, label, isDir),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
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
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
    if (action == null) {
      return Text(
        '—',
        style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      );
    }
    final applied = action!.status == ActionStatus.applied;
    return Row(
      children: [
        Icon(
          applied ? Icons.check_circle : Icons.subdirectory_arrow_right,
          size: 15,
          color: applied ? const Color(0xFF34C759) : scheme.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Tooltip(
            message: action!.target,
            waitDuration: const Duration(milliseconds: 350),
            child: Text(
              action!.target,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.primary,
                height: 1.25,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfidenceCell extends StatelessWidget {
  final OrganizeAction? action;
  const _ConfidenceCell({required this.action});

  @override
  Widget build(BuildContext context) {
    if (action == null) return const SizedBox.shrink();
    final v = action!.confidence.clamp(0.0, 1.0);
    final color = v >= 0.75
        ? const Color(0xFF34C759)
        : v >= 0.5
        ? const Color(0xFFFFB020)
        : Theme.of(context).colorScheme.error;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible so the bar gives way first: the cell's fixed parts alone
        // (spacing + percentage) already approach the column's minimum width,
        // and a rigid bar overflows as soon as the column is dragged narrow.
        Flexible(
          child: SizedBox(
            width: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: v),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: color.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(v * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _FooterBar extends StatelessWidget {
  final int fileCount;
  const _FooterBar({required this.fileCount});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final browser = context.watch<FileBrowserService>();
    final ai = context.watch<AiService>();
    final scheme = Theme.of(context).colorScheme;

    final String statusText;
    final Color statusColor;
    if (ai.isAnalyzing) {
      statusText = l10n.analyzing;
      statusColor = scheme.primary;
    } else if (ai.currentPlan != null &&
        ai.planBaseDir == browser.currentDirectory) {
      statusText = l10n.analysisComplete;
      statusColor = const Color(0xFF34C759);
    } else {
      statusText = l10n.notAnalyzed;
      statusColor = scheme.onSurfaceVariant;
    }

    final selCount = browser.selectionCount > 0
        ? browser.selectionCount
        : (browser.selectedFile != null ? 1 : 0);
    final style = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          Text(
            selCount > 0
                ? '${l10n.selectedCount(selCount)} · ${l10n.itemsCount(fileCount)}'
                : l10n.itemsCount(fileCount),
            style: style,
          ),
          if (browser.selectionCount > 0) ...[
            const SizedBox(width: 10),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: browser.clearSelection,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  l10n.clearSelection,
                  style: TextStyle(fontSize: 12.5, color: scheme.primary),
                ),
              ),
            ),
          ],
          const Spacer(),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(statusText, style: style),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPickFolder;
  const _EmptyState({required this.onPickFolder});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 64,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noFolderOpen,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPickFolder,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(l10n.openFolder),
          ),
        ],
      ),
    );
  }
}
