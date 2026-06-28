import 'package:flutter/material.dart';
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
import '../glass/glass_panel.dart';

/// Center pane: breadcrumb + actions, the file table with AI-suggestion and
/// confidence columns, and a status footer.
class MediaTable extends StatelessWidget {
  final String searchQuery;
  final VoidCallback onOrganize;
  final VoidCallback onPickFolder;

  const MediaTable({
    super.key,
    required this.searchQuery,
    required this.onOrganize,
    required this.onPickFolder,
  });

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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final browser = context.watch<FileBrowserService>();
    final ai = context.watch<AiService>();

    if (browser.currentDirectory == null) {
      return GlassPanel(
        radius: 24,
        elevated: true,
        child: _EmptyState(onPickFolder: onPickFolder),
      );
    }

    final query = searchQuery.trim().toLowerCase();
    final files = query.isEmpty
        ? browser.files
        : browser.files
              .where((f) => p.basename(f.path).toLowerCase().contains(query))
              .toList();

    // Index plan actions by their folder-relative source path for quick lookup.
    final actionBySource = <String, OrganizeAction>{};
    final plan = ai.currentPlan;
    final base = ai.planBaseDir;
    if (plan != null && base != null) {
      for (final a in plan.actions) {
        actionBySource[a.source] = a;
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          _TopBar(onOrganize: onOrganize, onPickFolder: onPickFolder),
          const _Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: _HeaderRow(l10n: l10n),
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
                        entry: file,
                        action: rel != null ? actionBySource[rel] : null,
                        selected: browser.selectedFile?.path == file.path,
                        onTap: () => browser.setSelectedFile(file),
                        onDoubleTap: () {
                          if (file.isDirectory) {
                            browser.setCurrentDirectory(file.path);
                            context.read<SettingsService>().pushRecent(
                              file.path,
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
          const _Divider(),
          _FooterBar(fileCount: browser.files.length),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      child: Row(
        children: [
          Expanded(child: _Breadcrumb(onPickFolder: onPickFolder)),
          const SizedBox(width: 4),
          Builder(
            builder: (context) {
              final settings = context.watch<SettingsService>();
              final dir = context.read<FileBrowserService>().currentDirectory;
              final pinned = dir != null && settings.isFavorite(dir);
              return IconButton(
                tooltip: l10n.favorites,
                onPressed: dir == null
                    ? null
                    : () => settings.toggleFavorite(dir),
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
            label: Text(l10n.organizeWithAi),
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
  const _HeaderRow({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      letterSpacing: 0.8,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Expanded(
          flex: 32,
          child: Text(l10n.colName.toUpperCase(), style: style),
        ),
        Expanded(
          flex: 10,
          child: Text(l10n.colType.toUpperCase(), style: style),
        ),
        Expanded(
          flex: 10,
          child: Text(l10n.colSize.toUpperCase(), style: style),
        ),
        Expanded(
          flex: 26,
          child: Text(l10n.colAiSuggestion.toUpperCase(), style: style),
        ),
        Expanded(
          flex: 16,
          child: Text(
            l10n.colConfidence.toUpperCase(),
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final FileEntry entry;
  final OrganizeAction? action;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _FileRow({
    required this.entry,
    required this.action,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.32),
                    scheme.primary.withValues(alpha: 0.20),
                  ],
                )
              : null,
          border: selected
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
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 32,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            FileLabelService.getIcon(label, isDir),
                            size: 18,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: name,
                                waitDuration: const Duration(milliseconds: 350),
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
                  Expanded(
                    flex: 10,
                    child: Text(
                      MediaTable.localizedType(l10n, label, isDir),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 10,
                    child: Text(
                      size,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(flex: 26, child: _SuggestionCell(action: action)),
                  Expanded(flex: 16, child: _ConfidenceCell(action: action)),
                ],
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
        SizedBox(
          width: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 5,
              backgroundColor: color.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(color),
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

    final style = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          Text(
            browser.selectedFile != null
                ? '${l10n.selectedCount(1)} · ${l10n.itemsCount(fileCount)}'
                : l10n.itemsCount(fileCount),
            style: style,
          ),
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
