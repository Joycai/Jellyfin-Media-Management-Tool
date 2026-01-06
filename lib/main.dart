import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/media_manager_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jellyfin Media Management Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005AC1), // A more professional Jellyfin-like blue
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.grey.shade50,
          selectedIconTheme: const IconThemeData(color: Color(0xFF005AC1), size: 28),
          unselectedIconTheme: IconThemeData(color: Colors.grey.shade600, size: 24),
          selectedLabelTextStyle: const TextStyle(
            color: Color(0xFF005AC1),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
          indicatorColor: const Color(0xFFD1E4FF),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
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

  final List<Widget> _screens = [
    const MediaManagerScreen(),
    const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_suggest_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Configuration options coming soon...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
            extended: false,
            minWidth: 80,
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
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.folder_copy_outlined),
                selectedIcon: Icon(Icons.folder_copy),
                label: Text('Manager'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                // Custom App Bar for a more integrated look
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedIndex == 0 ? 'Media Manager' : 'Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.help_outline),
                        onPressed: () {},
                        tooltip: 'Help',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _screens[_selectedIndex],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
