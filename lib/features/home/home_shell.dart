import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../features/community/presentation/community_store_screen.dart';
import '../../features/community/presentation/download_manager.dart';
import '../../features/identity/data/peer_identity.dart';
import '../library/library_screen.dart';
import '../reading/reading_screen.dart';
import '../settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.identity});

  final IdentityRepository identity;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Tabs are built on first visit.
  final Set<int> _built = <int>{0};

  void _select(int index) {
    if (_index == index) return;
    setState(() {
      _index = index;
      _built.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const LibraryScreen(),
          if (_built.contains(1))
            ReadingScreen(onBrowseLibrary: () => _select(0))
          else
            const SizedBox.shrink(),
          if (_built.contains(2))
            const CommunityStoreScreen()
          else
            const SizedBox.shrink(),
          if (_built.contains(3))
            const DownloadManagerScreen()
          else
            const SizedBox.shrink(),
          if (_built.contains(4))
            SettingsScreen(active: _index == 4, identity: widget.identity)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.22),
            ),
          ),
        ),
        child: NavigationBar(
          height: 66,
          elevation: 0,
          backgroundColor: theme.colorScheme.surface,
          indicatorColor: fade(AppColors.brass, 0.24),
          selectedIndex: _index,
          onDestinationSelected: _select,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories_rounded),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Reading',
            ),
            NavigationDestination(
              icon: Icon(Icons.store_outlined),
              selectedIcon: Icon(Icons.store_rounded),
              label: 'Community',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download_rounded),
              label: 'Downloads',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
