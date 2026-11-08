import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../data/settings_repository.dart';
import '../common/app_sheet.dart';
import '../reader/open_book.dart';
import 'widgets/book_preview.dart';
import 'widgets/book_sheets.dart';
import 'widgets/shelf_row.dart';
import 'widgets/spine_shelf_row.dart';
import 'widgets/wood_background.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _searching = false;
  bool _importing = false;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    if (_importing) return;
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        dialogTitle: 'Add books to LibReady',
        type: FileType.custom,
        allowedExtensions: const <String>['pdf', 'epub'],
      );
    } catch (_) {
      if (mounted) showToast(context, 'The file picker could not be opened.');
      return;
    }
    if (!mounted || files.isEmpty) return;
    await _importFiles(files);
  }

  Future<void> _importFiles(List<PlatformFile> files) async {
    setState(() => _importing = true);
    final repo = context.read<LibraryRepository>();
    final progress = ValueNotifier<_ImportProgress>(
      _ImportProgress(0, files.length, 'Preparing…'),
    );
    BuildContext? dialogContext;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return _ImportDialog(progress: progress);
        },
      ),
    );
    // Let the progress dialog reach the screen before the import starts.
    await WidgetsBinding.instance.endOfFrame;

    ImportOutcome? outcome;
    try {
      outcome = await repo.importFiles(
        files,
        onProgress: (done, total, name) {
          progress.value = _ImportProgress(done, total, name);
        },
      );
    } catch (_) {
      outcome = null;
    } finally {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      if (mounted) setState(() => _importing = false);
    }

    if (!mounted) return;
    if (outcome == null) {
      showToast(context, 'Those files could not be imported.');
    } else {
      showToast(context, outcome.message);
    }
  }

  void _openBook(Book book) {
    unawaited(openBook(context, book));
  }

  Future<void> _showBook(Book book) async {
    final action = await showBookActionsSheet(context, book);
    if (!mounted || action == null) return;
    final repo = context.read<LibraryRepository>();
    var fresh = repo.bookById(book.id);
    if (fresh == null) return;
    if (action == BookAction.readAgain) {
      await repo.restartReading(fresh);
      if (!mounted) return;
      fresh = repo.bookById(book.id) ?? fresh;
    }
    _openBook(fresh);
  }

  /// A single tap zooms the book forward instead of leaving the shelf. The
  /// preview keeps all metadata readable and offers the reading button.
  Future<void> _previewBook(Book book) async {
    final action = await showBookPreview(context, book);
    if (!mounted || action == null) return;
    if (action == BookPreviewAction.more) {
      await _showBook(book);
      return;
    }
    await _readBook(book);
  }

  Future<void> _readBook(Book book) async {
    final repo = context.read<LibraryRepository>();
    var fresh = repo.bookById(book.id) ?? book;
    if (fresh.isFinished) {
      await repo.restartReading(fresh);
      if (!mounted) return;
      fresh = repo.bookById(book.id) ?? fresh;
    }
    _openBook(fresh);
  }

  Future<void> _showOptions() async {
    final repo = context.read<LibraryRepository>();
    final settings = context.read<SettingsRepository>();
    await showAppSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Arrange the shelves',
                    style: serifStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Choose the look and order of your shelves.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SHELF STYLE',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.05,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  for (final display in ShelfDisplay.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        display == ShelfDisplay.covers
                            ? Icons.auto_stories_rounded
                            : Icons.view_week_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        display.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: settings.shelfDisplay == display
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        display.description,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: settings.shelfDisplay == display
                          ? Icon(
                              Icons.check_rounded,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        unawaited(settings.setShelfDisplay(display));
                        setSheetState(() {});
                      },
                    ),
                  const Divider(height: 22),
                  Text(
                    'ORDER BOOKS',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.05,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
                      trailing: repo.sortMode == mode
                          ? Icon(
                              Icons.check_rounded,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        repo.setSortMode(mode);
                        setSheetState(() {});
                      },
                    ),
                  if (settings.shelfDisplay == ShelfDisplay.covers) ...[
                    const Divider(height: 22),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Show dates above covers',
                        style: TextStyle(fontSize: 14.5),
                      ),
                      subtitle: Text(
                        'The date you last opened each book.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: settings.showShelfDates,
                      onChanged: (value) {
                        unawaited(settings.setShowShelfDates(value));
                        setSheetState(() {});
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _toggleSearch() {
    final repo = context.read<LibraryRepository>();
    setState(() => _searching = !_searching);
    if (!_searching) {
      _search.clear();
      repo.setQuery('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LibraryRepository>();
    final settings = context.watch<SettingsRepository>();

    return Scaffold(
      backgroundColor: const Color(0xFF3E2413),
      floatingActionButton: _importing
          ? null
          : FloatingActionButton.extended(
              onPressed: _pickFiles,
              backgroundColor: const Color(0xFFCFA66B),
              foregroundColor: const Color(0xFF2A1B0C),
              elevation: 5,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add books',
                style:
                    TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3),
              ),
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(painter: WoodBackgroundPainter()),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(repo, settings),
                Expanded(child: _buildBody(repo, settings)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(LibraryRepository repo, SettingsRepository settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LibReady',
                      style: serifStyle(
                        fontSize: 31,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF7EBD4),
                        letterSpacing: 0.3,
                      ).copyWith(
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _statsLine(repo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.35,
                        color: const Color(0xFFE4D2B4).withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              _WoodButton(
                icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                tooltip: _searching ? 'Close search' : 'Search library',
                active: _searching,
                onTap: _toggleSearch,
              ),
              const SizedBox(width: 7),
              _WoodButton(
                icon: Icons.tune_rounded,
                tooltip: 'Sort and display',
                onTap: _showOptions,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _searching
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: repo.setQuery,
                      style: const TextStyle(
                        color: Color(0xFFF3E8D2),
                        fontSize: 15,
                      ),
                      cursorColor: AppColors.brass,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search title, author or description',
                        hintStyle: TextStyle(
                          color: const Color(0xFFE4D2B4).withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: Color(0xFFD9C6A6),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.24),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.brass.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 33,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChipView(
                  label: LibraryFilter.all.label,
                  count: repo.bookCount,
                  selected: repo.filter == LibraryFilter.all,
                  onTap: () => repo.setFilter(LibraryFilter.all),
                ),
                _FilterChipView(
                  label: LibraryFilter.reading.label,
                  count: repo.readingCount,
                  selected: repo.filter == LibraryFilter.reading,
                  onTap: () => repo.setFilter(LibraryFilter.reading),
                ),
                _FilterChipView(
                  label: LibraryFilter.finished.label,
                  count: repo.finishedCount,
                  selected: repo.filter == LibraryFilter.finished,
                  onTap: () => repo.setFilter(LibraryFilter.finished),
                ),
                _FilterChipView(
                  label: LibraryFilter.favorites.label,
                  count: repo.books.where((book) => book.isFavorite).length,
                  selected: repo.filter == LibraryFilter.favorites,
                  onTap: () => repo.setFilter(LibraryFilter.favorites),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  String _statsLine(LibraryRepository repo) {
    final parts = <String>[
      '${repo.bookCount} ${repo.bookCount == 1 ? 'book' : 'books'}',
    ];
    if (repo.readingCount > 0) parts.add('${repo.readingCount} in progress');
    if (repo.finishedCount > 0) parts.add('${repo.finishedCount} finished');
    return parts.join('  ·  ');
  }

  Widget _buildBody(LibraryRepository repo, SettingsRepository settings) {
    if (repo.isLoading) {
      return const _WoodMessage(
        icon: Icons.auto_stories_rounded,
        title: 'Opening the library…',
        message: 'Your books stay on this device.',
        showSpinner: true,
      );
    }

    if (repo.lastError != null && repo.bookCount == 0) {
      return _WoodMessage(
        icon: Icons.error_outline_rounded,
        title: 'The library could not be opened',
        message: 'Check that the app has storage access, then try again.',
        actionLabel: 'Try again',
        onAction: () => repo.reload(),
      );
    }

    if (repo.bookCount == 0) {
      return _WoodMessage(
        icon: Icons.auto_stories_rounded,
        title: 'Your shelves are empty',
        message:
            'Add PDF and EPUB files from this device.\nNothing is uploaded — '
            'your library never leaves this phone.',
        actionLabel: 'Add your first book',
        onAction: _pickFiles,
      );
    }

    final books = repo.visibleBooks;
    if (books.isEmpty) {
      return _WoodMessage(
        icon: Icons.search_off_rounded,
        title: 'No books found',
        message: repo.query.trim().isEmpty
            ? 'Nothing matches this shelf right now.'
            : 'Nothing matches “${repo.query.trim()}”.',
        actionLabel: 'Clear filters',
        onAction: () {
          repo.setFilter(LibraryFilter.all);
          _search.clear();
          repo.setQuery('');
        },
      );
    }

    final spines = settings.shelfDisplay == ShelfDisplay.spines;
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = math.max(240.0, constraints.maxWidth - 32);

        if (spines) {
          final maxHeight = (constraints.maxWidth * 0.40).clamp(136.0, 178.0);
          final rows = _packSpineRows(books, usable - 10);
          return ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 128),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == rows.length - 1 ? 0 : 20,
                ),
                child: SpineShelfRow(
                  books: rows[index],
                  maxHeight: maxHeight,
                  onOpen: _previewBook,
                  onLongPress: _showBook,
                ),
              );
            },
          );
        }

        final columns = (usable / 112).floor().clamp(2, 5);
        final slotWidth = usable / columns;
        final coverWidth = (slotWidth * 0.68).clamp(68.0, 128.0);
        final coverHeight = coverWidth * 1.48;

        final rows = <List<Book>>[];
        for (var i = 0; i < books.length; i += columns) {
          rows.add(
            books.sublist(i, math.min(i + columns, books.length)),
          );
        }

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 128),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : 32,
              ),
              child: ShelfRow(
                books: rows[index],
                slotWidth: slotWidth,
                coverWidth: coverWidth,
                coverHeight: coverHeight,
                showDates: settings.showShelfDates,
                onOpen: _previewBook,
                onLongPress: _showBook,
              ),
            );
          },
        );
      },
    );
  }

  /// Packs books shoulder to shoulder, starting a new board whenever the next
  /// spine would not fit. Keeps the packed look of a real bookcase.
  List<List<Book>> _packSpineRows(List<Book> books, double maxWidth) {
    final rows = <List<Book>>[];
    var current = <Book>[];
    var used = 0.0;
    for (final book in books) {
      final width = spineWidthFor(book) + spineGap;
      if (current.isNotEmpty && used + width > maxWidth) {
        rows.add(current);
        current = <Book>[];
        used = 0;
      }
      current.add(book);
      used += width;
    }
    if (current.isNotEmpty) rows.add(current);
    return rows;
  }
}

class _WoodButton extends StatelessWidget {
  const _WoodButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: active ? 0.32 : 0.18),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(
              icon,
              size: 21,
              color: active ? AppColors.brass : const Color(0xFFF3E8D2),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChipView extends StatelessWidget {
  const _FilterChipView({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? AppColors.brass.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              count > 0 ? '$label  $count' : label,
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.25,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? const Color(0xFF2A1B0C)
                    : const Color(0xFFE4D2B4).withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WoodMessage extends StatelessWidget {
  const _WoodMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.showSpinner = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.brass,
                ),
              )
            else
              Icon(
                icon,
                size: 50,
                color: const Color(0xFFE4D2B4).withValues(alpha: 0.6),
              ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: serifStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFF7EBD4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: const Color(0xFFE4D2B4).withValues(alpha: 0.72),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFCFA66B),
                  foregroundColor: const Color(0xFF2A1B0C),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportProgress {
  const _ImportProgress(this.done, this.total, this.name);

  final int done;
  final int total;
  final String name;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

class _ImportDialog extends StatelessWidget {
  const _ImportDialog({required this.progress});

  final ValueListenable<_ImportProgress> progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 34),
      child: Container(
        width: 330,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.brass.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 26,
            ),
          ],
        ),
        child: ValueListenableBuilder<_ImportProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Adding to your library',
                        style: serifStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: value.fraction,
                    minHeight: 5,
                    backgroundColor:
                        theme.colorScheme.outline.withValues(alpha: 0.28),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  value.total == 0
                      ? 'Preparing…'
                      : '${value.done} of ${value.total}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
