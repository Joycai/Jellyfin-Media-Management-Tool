import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_service.dart';
import '../services/file_browser_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import '../shortcuts/app_shortcuts.dart';
import '../theme/design_tokens.dart';
import '../utils/format.dart';
import '../widgets/ai/ai_assistant_panel.dart';
import '../widgets/ai/history_popover.dart';
import '../widgets/ai/organize_history_screen.dart';
import '../widgets/dialogs/title_hint_dialog.dart';
import '../widgets/file_browser/file_context_menu.dart';
import '../widgets/file_browser/media_table.dart';
import '../widgets/scrape/scrape_flow.dart';
import '../widgets/settings/settings_screen.dart';
import '../widgets/shell/app_shell.dart';
import '../widgets/shell/app_title_bar.dart';
import '../widgets/shell/window_state.dart';
import '../widgets/sidebar/app_sidebar.dart';
import '../widgets/tasks/tasks_screen.dart';
import '../widgets/ui/glass_surface.dart';

/// 应用外壳：一条 48px 统一顶栏之下的三栏骨架（2.6）。
///
/// `48 顶栏 / 244 侧栏 / flex 主内容 / 352 右面板 / 28 状态栏`，两个断点：
/// < 1180 侧栏折叠成 64 图标栏，< 1400 右面板默认收起改为浮层。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _search = '';
  AppSection _section = AppSection.files;
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();

  /// 右面板的显隐**按分区记忆**（2.6）。宽度断点只决定默认值。
  final Map<AppSection, bool?> _panelOpen = {};

  /// 侧栏被用户手动折叠；null = 跟随断点。
  bool? _sidebarCollapsed;

  /// 历史角标只在「最近一条操作可撤销且用户尚未打开过浮层」时出现，
  /// 打开即消失，不做数字计数（5.4）。
  bool _historySeen = false;

  /// 顶栏历史按钮的位置，浮层锚在它下方。
  final _historyButtonKey = GlobalKey();

  /// 浮层打开中 —— 按钮保持强调色底，与其他动作按钮区分（5.4）。
  bool _historyOpen = false;

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
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
          onPressed: () => setState(() => _section = AppSection.tasks),
        ),
      ),
    );
  }

  /// Scrapes metadata for the focused row, or for the whole folder when
  /// nothing is focused. Deliberately single-target — see [startScrapeFlow].
  Future<void> _scrape() async {
    if (!_onFiles) return;
    final browser = context.read<FileBrowserService>();
    final dir = browser.currentDirectory;
    if (dir == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.scrapeNoFolder)));
      return;
    }
    await startScrapeFlow(context, target: browser.selectedFile, baseDir: dir);
  }

  // ── Keyboard shortcuts ────────────────────────────────────────────────────
  // Bindings and their descriptions live in lib/shortcuts/app_shortcuts.dart;
  // this only supplies the callbacks. Ids with no entry here stay unbound.

  /// Shortcuts that act on the file table are no-ops outside the Files tab.
  bool get _onFiles => _section == AppSection.files;

  void _selectAll() {
    if (!_onFiles) return;
    final browser = context.read<FileBrowserService>();
    browser.selectAll(MediaTable.visibleFiles(browser.files, _search));
  }

  /// Esc unwinds one layer at a time: an active search first, then focus, then
  /// the selection. (A dialog on top would have consumed the key before us.)
  void _escape() {
    if (_search.isNotEmpty) {
      _searchController.clear();
      setState(() => _search = '');
      return;
    }
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
      return;
    }
    context.read<FileBrowserService>().clearSelection();
  }

  Future<void> _renameFocused() async {
    if (!_onFiles) return;
    final entry = context.read<FileBrowserService>().selectedFile;
    if (entry == null) return;
    await renameEntry(context, entry);
  }

  Future<void> _deleteSelection() async {
    if (!_onFiles) return;
    final browser = context.read<FileBrowserService>();
    // Mirrors the context menu: an explicit multi-selection wins, otherwise
    // the focused row.
    final targets = browser.selectedEntries.isNotEmpty
        ? browser.selectedEntries
        : [if (browser.selectedFile != null) browser.selectedFile!];
    await deleteEntries(context, targets);
  }

  void _toggleFavorite() {
    if (!_onFiles) return;
    final dir = context.read<FileBrowserService>().currentDirectory;
    if (dir == null) return;
    context.read<SettingsService>().toggleFavorite(dir);
  }

  Future<void> _openHistory() async {
    final box =
        _historyButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      // 顶栏不在场（例如从别处触发快捷键）时退回到独立窗口，而不是把浮层
      // 钉在屏幕角落。
      OrganizeHistoryScreen.show(context);
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    setState(() {
      _historySeen = true;
      _historyOpen = true;
    });
    await showHistoryPopover(context, anchor: origin & box.size);
    if (mounted) setState(() => _historyOpen = false);
  }

  Map<AppShortcutId, VoidCallback> _shortcutHandlers() {
    final browser = context.read<FileBrowserService>();
    return {
      AppShortcutId.focusSearch: _searchFocus.requestFocus,
      AppShortcutId.refresh: browser.refresh,
      AppShortcutId.parentFolder: browser.goToParent,
      AppShortcutId.openFolder: _pickFolder,
      AppShortcutId.selectAll: _selectAll,
      AppShortcutId.escape: _escape,
      AppShortcutId.rename: _renameFocused,
      AppShortcutId.delete: _deleteSelection,
      AppShortcutId.organize: _organize,
      AppShortcutId.scrape: _scrape,
      AppShortcutId.toggleFavorite: _toggleFavorite,
      AppShortcutId.history: _openHistory,
      AppShortcutId.settings: () => SettingsScreen.show(context),
      AppShortcutId.sectionFiles: () =>
          setState(() => _section = AppSection.files),
      AppShortcutId.sectionLibrary: () =>
          setState(() => _section = AppSection.library),
      AppShortcutId.sectionTasks: () =>
          setState(() => _section = AppSection.tasks),
    };
  }

  @override
  Widget build(BuildContext context) {
    // 顶栏与状态栏都要跟着窗口状态重画，所以这里订阅一次。
    WindowStateScope.of(context);
    final hasUndoable = context.select<HistoryService, bool>(
      (h) => h.entries.isNotEmpty,
    );

    return Scaffold(
      body: CallbackShortcuts(
        bindings: buildShortcutBindings(_shortcutHandlers()),
        // Shortcuts are dispatched up the focus chain, so without a focused
        // node inside this subtree nothing reaches CallbackShortcuts and every
        // binding is dead until the user clicks something. skipTraversal keeps
        // this scope holder out of the Tab order.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: AppShell(
            titleBar: AppTitleBar(
              section: _section,
              onSection: (s) => setState(() => _section = s),
              runningTasks: context.select<TaskService, int>(
                (t) => t.runningCount,
              ),
              searchFocus: _searchFocus,
              searchController: _searchController,
              onSearch: (v) => setState(() => _search = v),
              searchShortcut: shortcutLabel(AppShortcutId.focusSearch),
              onHistory: _openHistory,
              historyButtonKey: _historyButtonKey,
              onRefresh: context.read<FileBrowserService>().refresh,
              onSettings: () => SettingsScreen.show(context),
              historyHasNews: hasUndoable && !_historySeen,
              historyOpen: _historyOpen,
              historyEmpty: !hasUndoable,
            ),
            statusBar: _statusBar(),
            body: LayoutBuilder(builder: (context, c) => _body(c.maxWidth)),
          ),
        ),
      ),
    );
  }

  Widget _body(double width) {
    switch (_section) {
      case AppSection.files:
        // 断点只决定默认值；用户在这个分区做过的选择一直有效。
        final collapsed =
            _sidebarCollapsed ?? (width < AppSizes.breakpointCompact);
        final panelOpen =
            _panelOpen[_section] ?? (width >= AppSizes.breakpointPanel);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSidebar(
              collapsed: collapsed,
              onToggleCollapsed: () =>
                  setState(() => _sidebarCollapsed = !collapsed),
            ),
            Expanded(
              child: MediaTable(
                searchQuery: _search,
                onOrganize: _organize,
                onPickFolder: _pickFolder,
                panelOpen: panelOpen,
                onTogglePanel: () =>
                    setState(() => _panelOpen[_section] = !panelOpen),
              ),
            ),
            // 180ms ease-in-out —— 抽屉与面板的统一时长（1.4f）。
            AnimatedContainer(
              duration: AppMotion.respecting(context, AppMotion.panel),
              curve: AppMotion.panelCurve,
              width: panelOpen ? AppSizes.rightPanel : 0,
              child: panelOpen
                  ? const AiAssistantPanel()
                  : const SizedBox.shrink(),
            ),
          ],
        );
      case AppSection.library:
        return const _LibraryPlaceholder();
      case AppSection.tasks:
        return const TasksScreen();
    }
  }

  /// 状态栏 h28 · 仅文字与进度，无按钮。
  Widget _statusBar() {
    final l10n = AppLocalizations.of(context)!;
    final t = context.tokens;
    if (_section != AppSection.files) {
      return AppStatusBar(leading: [Text(_sectionLabel(l10n))]);
    }
    final browser = context.watch<FileBrowserService>();
    final visible = MediaTable.visibleFiles(browser.files, _search);
    final bytes = visible.fold<int>(0, (sum, e) => sum + e.size);
    final ai = context.watch<AiService>();
    // 计数与选中数由列表面板自己的页脚讲（3.1）；状态栏讲的是「这个文件夹有多
    // 大、AI 走到哪一步了」。两个地方都写「已选 N 项」的时候它们还会打架 ——
    // 面板把聚焦行算作 1，状态栏只算显式多选。
    return AppStatusBar(
      leading: [
        Text(
          l10n.statusTotalSize(formatBytes(bytes, zero: '0 B')),
          style: AppTypeScale.monoSmall.copyWith(color: t.textMuted),
        ),
      ],
      trailing: [
        if (ai.currentPlan != null)
          StatusDot(color: t.success, label: l10n.planReady)
        else if (browser.currentDirectory != null)
          StatusDot(
            color: t.textMuted,
            label: p.basename(browser.currentDirectory!),
          ),
      ],
    );
  }

  String _sectionLabel(AppLocalizations l10n) => switch (_section) {
    AppSection.files => l10n.tabFiles,
    AppSection.library => l10n.tabLibrary,
    AppSection.tasks => l10n.tabTasks,
  };
}

/// 媒体库分区还没有实现（03 的网格 / 详情稿）。
///
/// 按任务要求：**先以设计稿的「占位」方式完成**，能力本身进 backlog
/// （`docs/spec/ui-redesign/backlog.md`）。占位仍然走完整的令牌与卡片规范，
/// 这样它接上真实数据时不需要再改一遍样式。
class _LibraryPlaceholder extends StatelessWidget {
  const _LibraryPlaceholder();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(AppSizes.contentPaddingH),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xxl40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: t.aiSurface,
                  borderRadius: BorderRadius.circular(AppRadii.panel),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.video_library_rounded,
                  size: 24,
                  color: t.aiText,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.tabLibrary,
                style: AppTypeScale.heading.copyWith(color: t.textTitle),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.comingSoon,
                style: AppTypeScale.caption.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
