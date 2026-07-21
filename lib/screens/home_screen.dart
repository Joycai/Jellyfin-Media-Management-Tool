import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_service.dart';
import '../services/file_browser_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai/ai_assistant_panel.dart';
import '../widgets/dialogs/title_hint_dialog.dart';
import '../widgets/file_browser/media_table.dart';
import '../widgets/ai/organize_history_screen.dart';
import '../widgets/glass/glass_panel.dart';
import '../widgets/settings/settings_screen.dart';
import '../widgets/sidebar/app_sidebar.dart';
import '../widgets/tasks/tasks_screen.dart';

/// App shell under the native title bar: a full-width header (brand · section
/// tabs · search · actions) over the three glass panes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Section { files, library, tasks }

class _HomeScreenState extends State<HomeScreen> {
  String _search = '';
  _Section _section = _Section.files;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final browser = context.read<FileBrowserService>();
    final settings = context.read<SettingsService>();
    final dir = await FilePicker.getDirectoryPath();
    if (dir != null) {
      browser.setCurrentDirectory(dir);
      settings.pushRecent(dir);
    }
  }

  Future<void> _organize() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final browser = context.read<FileBrowserService>();
    final ai = context.read<AiService>();
    final tasks = context.read<TaskService>();
    final dir = browser.currentDirectory;
    if (dir == null) return;
    if (!ai.isConfigured) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.aiNotConfigured)));
      return;
    }
    // Explicitly multi-selected entries → organize only those; an empty
    // selection means the whole folder (plain focus clicks don't count).
    final selection = browser.selectedPaths;

    final result = await showTitleHintDialog(
      context,
      folderName: p.basename(dir),
    );
    if (result == null) return; // user cancelled
    final typeHint = switch (result.kind) {
      MediaKindHint.movie => 'movie',
      MediaKindHint.series => 'series',
      MediaKindHint.auto => null,
    };

    // Hand the work to TaskService — the Tasks tab shows live progress.
    tasks.startAnalyze(
      ai: ai,
      baseDir: dir,
      titleHint: result.title.isEmpty ? null : result.title,
      mediaTypeHint: typeHint,
      onlyPaths: selection.isEmpty ? null : selection,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.tasksAnalyzeStarted),
        // A SnackBar with an action defaults to persist:true — it would sit
        // there forever instead of timing out. This one is a "started" notice,
        // not something the user has to answer, so opt back into auto-dismiss.
        persist: false,
        action: SnackBarAction(
          label: l10n.tabTasks,
          onPressed: () => setState(() => _section = _Section.tasks),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<GlassTheme>()!;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              _searchFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _searchFocus.requestFocus(),
        },
        child: Container(
          decoration: BoxDecoration(gradient: glass.backdrop),
          child: Column(
            children: [
              _Header(
                section: _section,
                onSection: (s) => setState(() => _section = s),
                searchFocus: _searchFocus,
                onSearch: (v) => setState(() => _search = v),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_section) {
      case _Section.files:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 244, child: AppSidebar()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MediaTable(
                  searchQuery: _search,
                  onOrganize: _organize,
                  onPickFolder: _pickFolder,
                ),
              ),
            ),
            const SizedBox(width: 352, child: AiAssistantPanel()),
          ],
        );
      case _Section.library:
        return _ComingSoon(
          icon: Icons.video_library_rounded,
          label: AppLocalizations.of(context)!.tabLibrary,
        );
      case _Section.tasks:
        return const TasksScreen();
    }
  }
}

class _Header extends StatelessWidget {
  final _Section section;
  final ValueChanged<_Section> onSection;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearch;

  const _Header({
    required this.section,
    required this.onSection,
    required this.searchFocus,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).extension<GlassTheme>()!;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: glass.sidebarFill,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text(
              'J',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // NOT Flexible: a loose flex child here would claim half the Row's
          // free space (splitting it with the search Expanded) and dump its
          // unused allocation as trailing space AFTER the last icon button,
          // pushing the right-side icons away from the window edge.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              l10n.appBrand,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 22,
            color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
          const SizedBox(width: 8),
          _NavTab(
            icon: Icons.folder_rounded,
            label: l10n.tabFiles,
            selected: section == _Section.files,
            onTap: () => onSection(_Section.files),
          ),
          _NavTab(
            icon: Icons.video_library_rounded,
            label: l10n.tabLibrary,
            selected: section == _Section.library,
            onTap: () => onSection(_Section.library),
          ),
          _NavTab(
            icon: Icons.bolt_rounded,
            label: l10n.tabTasks,
            selected: section == _Section.tasks,
            onTap: () => onSection(_Section.tasks),
            badge: context.watch<TaskService>().runningCount,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    focusNode: searchFocus,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: l10n.searchHint,
                      filled: true,
                      fillColor: scheme.surface.withValues(alpha: 0.35),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '⌘K',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(minWidth: 0),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.historyTitle,
            onPressed: () => OrganizeHistoryScreen.show(context),
            icon: const Icon(Icons.history_rounded),
            style: IconButton.styleFrom(
              backgroundColor: scheme.surface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: l10n.refresh,
            onPressed: context.read<FileBrowserService>().refresh,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              backgroundColor: scheme.surface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: l10n.settings,
            onPressed: () => SettingsScreen.show(context),
            icon: const Icon(Icons.settings_outlined),
            style: IconButton.styleFrom(
              backgroundColor: scheme.surface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Small running-task count rendered as a pill next to the label. 0 hides it.
  final int badge;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected
            ? scheme.surface.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ComingSoon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GlassPanel(
        radius: 24,
        elevated: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.comingSoon,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
