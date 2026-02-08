import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'screens/media_manager_screen.dart';
import 'services/settings_service.dart';
import 'services/file_browser_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  final settingsService = SettingsService();
  await settingsService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider(create: (_) => FileBrowserService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return MaterialApp(
      title: 'Jellyfin Media Management Tool',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      locale: settings.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005AC1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005AC1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainWorkspace(),
    );
  }
}

class MainWorkspace extends StatefulWidget {
  const MainWorkspace({super.key});

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();

    final List<Widget> screens = [
      const MediaManagerScreen(),
      _buildSettingsScreen(context, l10n, settings),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            leading: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_fix_high,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.folder_copy_outlined),
                selectedIcon: const Icon(Icons.folder_copy),
                label: Text(l10n.manager),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(l10n.settings),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedIndex == 0 ? l10n.mediaManager : l10n.settings,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: screens[_selectedIndex],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsScreen(BuildContext context, AppLocalizations l10n, SettingsService settings) {
    final String currentLang = settings.locale?.languageCode ?? 
                               Localizations.localeOf(context).languageCode;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(l10n.themeMode, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.light, label: Text(l10n.light), icon: const Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text(l10n.dark), icon: const Icon(Icons.dark_mode)),
            ButtonSegment(value: ThemeMode.system, label: Text(l10n.system), icon: const Icon(Icons.brightness_auto)),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (Set<ThemeMode> newSelection) {
            settings.setThemeMode(newSelection.first);
          },
        ),
        const SizedBox(height: 32),
        Text(l10n.language, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('English'),
              selected: currentLang == 'en',
              onSelected: (selected) {
                if (selected) settings.setLocale(const Locale('en'));
              },
            ),
            ChoiceChip(
              label: const Text('中文'),
              selected: currentLang == 'zh',
              onSelected: (selected) {
                if (selected) settings.setLocale(const Locale('zh'));
              },
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Text(l10n.editSearchSites, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showEditSiteDialog(context, null, settings, l10n),
              tooltip: l10n.addSite,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...settings.searchSites.asMap().entries.map((entry) {
          final index = entry.key;
          final site = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(site.name),
              subtitle: Text(site.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditSiteDialog(context, index, settings, l10n),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      final newSites = List<SearchSite>.from(settings.searchSites);
                      newSites.removeAt(index);
                      settings.updateSearchSites(newSites);
                    },
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: settings.openConfigFolder,
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.openConfigFolder),
          ),
        ),
      ],
    );
  }

  Future<void> _showEditSiteDialog(BuildContext context, int? index, SettingsService settings, AppLocalizations l10n) async {
    final site = index != null ? settings.searchSites[index] : null;
    final nameController = TextEditingController(text: site?.name);
    final urlController = TextEditingController(text: site?.url);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? l10n.addSite : l10n.editSearchSites),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: l10n.siteName),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: l10n.searchUrl,
                hintText: 'https://...{keyword}...{lang}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.save)),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
      final newSites = List<SearchSite>.from(settings.searchSites);
      final newSite = SearchSite(name: nameController.text, url: urlController.text);
      if (index == null) {
        newSites.add(newSite);
      } else {
        newSites[index] = newSite;
      }
      settings.updateSearchSites(newSites);
    }
  }
}
