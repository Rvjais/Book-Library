import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/formatting.dart';
import '../../data/library_repository.dart';
import '../../data/library_types.dart';
import '../../data/reader_settings.dart';
import '../../data/settings_repository.dart';
import '../common/app_sheet.dart';
import 'widgets/reader_settings_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<int> _storage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _storage = context.read<LibraryRepository>().storageBytes();
  }

  void _refreshStorage() {
    setState(() {
      _storage = context.read<LibraryRepository>().storageBytes();
    });
  }

  Future<void> _chooseSort(SettingsRepository settings) async {
    final library = context.read<LibraryRepository>();
    await showAppSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sort books by',
                    style: serifStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final mode in SortMode.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      trailing: library.sortMode == mode
                          ? Icon(
                              Icons.check_rounded,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        library.setSortMode(mode);
                        unawaited(settings.setSortMode(mode));
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pruneMissing() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final removed = await context.read<LibraryRepository>().pruneMissingFiles();
      if (!mounted) return;
      showToast(
        context,
        removed == 0
            ? 'All book files are present.'
            : 'Removed $removed missing ${removed == 1 ? 'book' : 'books'}.',
      );
      _refreshStorage();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEverything() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete every book?',
      message:
          'All books, covers, bookmarks and reading progress will be erased '
          'from this device. This cannot be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<LibraryRepository>().deleteEverything();
      if (!mounted) return;
      showToast(context, 'Your library was cleared.');
      _refreshStorage();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetReading(SettingsRepository settings) async {
    await settings.updateReader(const ReaderSettings());
    if (!mounted) return;
    showToast(context, 'Reading settings reset to their defaults.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsRepository>();
    final library = context.watch<LibraryRepository>();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surface,
                    theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          if (_busy)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Text(
                  'Settings',
                  style: serifStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Make the library and the page feel like yours.',
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('Appearance'),
                _SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Theme',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final mode in ThemeMode.values)
                                ChoiceChip(
                                  label: Text(_themeModeLabel(mode)),
                                  selected: settings.themeMode == mode,
                                  onSelected: (_) =>
                                      unawaited(settings.setThemeMode(mode)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The reader can still use its own paper theme.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionTitle('Library'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.sort_rounded,
                      title: 'Sort books by',
                      subtitle: settings.sortMode.label,
                      onTap: () => unawaited(_chooseSort(settings)),
                    ),
                    _SwitchRow(
                      icon: Icons.calendar_today_rounded,
                      title: 'Show dates above books',
                      value: settings.showShelfDates,
                      onChanged: (value) =>
                          unawaited(settings.setShowShelfDates(value)),
                    ),
                    _SettingsRow(
                      icon: Icons.sd_storage_outlined,
                      title: 'Storage used',
                      subtitleWidget: FutureBuilder<int>(
                        future: _storage,
                        builder: (context, snapshot) {
                          final text = snapshot.hasData
                              ? formatBytes(snapshot.data!)
                              : 'Calculating…';
                          return Text(
                            text,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.find_in_page_outlined,
                      title: 'Check for missing files',
                      subtitle: 'Drop entries whose book file has vanished.',
                      onTap: _busy ? null : _pruneMissing,
                    ),
                    _SettingsRow(
                      icon: Icons.delete_forever_outlined,
                      title: 'Delete all books',
                      subtitle: 'Erase books, covers, bookmarks and progress.',
                      color: theme.colorScheme.error,
                      onTap: _busy ? null : _deleteEverything,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionTitle('Reading defaults'),
                _SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                      child: ReaderSettingsPanel(
                        settings: settings.reader,
                        onChanged: (value) =>
                            unawaited(settings.updateReader(value)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_resetReading(settings)),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset reading settings'),
                  ),
                ),
                const SizedBox(height: 18),
                const _SectionTitle('About'),
                _SettingsCard(
                  children: [
                    const _SettingsRow(
                      icon: Icons.auto_stories_rounded,
                      title: 'LibReady',
                      subtitle: 'Version 1.0.0  ·  PDF & EPUB reader',
                    ),
                    const _SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      title: 'Offline by design',
                      subtitle:
                          'No accounts, no cloud, no tracking. Every book and '
                          'bookmark stays on this device.',
                    ),
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      title: 'Open source licences',
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: 'LibReady',
                          applicationVersion: '1.0.0',
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    '${library.bookCount} books in your library',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.3,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.62),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        icon,
        size: 21,
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          color: color ?? theme.colorScheme.onSurface,
        ),
      ),
      subtitle: subtitleWidget ??
          (subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
      onTap: onTap,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      secondary: Icon(
        icon,
        size: 21,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 14.5, color: theme.colorScheme.onSurface),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
