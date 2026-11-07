// ignore_for_file: unused_import
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/formatting.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../../data/reader_settings.dart';
import '../../data/settings_repository.dart';
import '../common/app_sheet.dart';
import '../../reader/engines/epub_engine.dart';
import '../../reader/engines/pdf_engine.dart';
import '../../reader/engines/reader_engine.dart';
import '../../reader/widgets/book_pager.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/reader_dialogs.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/search_sheet.dart';
import 'widgets/toc_sheet.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final LibraryRepository _library;
  late final SettingsRepository _settingsRepo;

  ReaderSettings _settings = const ReaderSettings();
  ReaderEngine? _engine;
  int _pageIndex = 0;

  bool _booted = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _chromeVisible = true;
  bool _closing = false;
  String? _error;
  double _layoutProgress = 0;
  int _generation = 0;

  Size? _openedSize;
  EdgeInsets? _openedInsets;

  Timer? _saveTimer;
  Timer? _settingsTimer;
  double? _sliderValue;

  List<Bookmark> _bookmarks = const <Bookmark>[];

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryRepository>();
    _settingsRepo = context.read<SettingsRepository>();
    _settings = _settingsRepo.reader;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_booted) {
      _booted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openEngine());
      });
      return;
    }
    if (!widget.book.isEpub || _engine == null || _loading) return;
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    if (_layoutChanged(size, insets)) {
      unawaited(_reopenForLayout());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _settingsTimer?.cancel();
    final engine = _engine;
    if (engine != null) unawaited(engine.dispose());
    super.dispose();
  }

  bool _layoutChanged(Size size, EdgeInsets insets) {
    final oldSize = _openedSize;
    if (oldSize == null) return true;
    return (oldSize.width - size.width).abs() > 1 ||
        (oldSize.height - size.height).abs() > 1 ||
        _openedInsets != insets;
  }

  Size _contentSize(Size size, EdgeInsets insets) {
    final width = math.max(
      120.0,
      size.width - insets.horizontal - _settings.margins * 2,
    );
    final height = math.max(
      120.0,
      size.height - insets.vertical - _settings.margins * 0.9 * 2,
    );
    return Size(width, height);
  }

  Future<void> _openEngine({ReadingPosition? at}) async {
    final generation = ++_generation;
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final hadEngine = _engine != null;
    final start = at ?? widget.book.readingPosition;

    setState(() {
      _loading = !hadEngine;
      _refreshing = hadEngine;
      _layoutProgress = 0;
      if (!hadEngine) _error = null;
      _openedSize = size;
      _openedInsets = insets;
    });

    try {
      final ReaderEngine engine;
      if (widget.book.isEpub) {
        engine = await EpubReaderEngine.open(
          widget.book,
          _settings,
          _contentSize(size, insets),
          onProgress: (progress) {
            if (!mounted || generation != _generation) return;
            setState(() => _layoutProgress = progress);
          },
        );
      } else {
        engine = await PdfReaderEngine.open(widget.book);
      }

      if (!mounted || generation != _generation) {
        await engine.dispose();
        return;
      }

      final page = engine
          .pageForPosition(start)
          .clamp(0, math.max(0, engine.pageCount - 1))
          .toInt();
      final previous = _engine;
      setState(() {
        _engine = engine;
        _pageIndex = page;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      if (previous != null) unawaited(previous.dispose());
      unawaited(_loadBookmarks());
    } catch (error, stack) {
      debugPrint('Could not open book: $error\n$stack');
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reopenForLayout() async {
    final engine = _engine;
    if (engine == null) return;
    final position = engine.positionForPage(_pageIndex);
    await _openEngine(at: position);
  }

  Future<void> _reopenForSettings() async {
    final engine = _engine;
    if (engine == null) return;
    final position = engine.positionForPage(_pageIndex);
    await _openEngine(at: position);
  }

  void _applySettings(ReaderSettings value) {
    final previous = _settings;
    setState(() => _settings = value);
    unawaited(_settingsRepo.updateReader(value));

    final typographyChanged =
        previous.fontSize != value.fontSize ||
            previous.lineHeight != value.lineHeight ||
            previous.margins != value.margins ||
            previous.serif != value.serif ||
            previous.justify != value.justify;

    if (typographyChanged && widget.book.isEpub) {
      _settingsTimer?.cancel();
      _settingsTimer = Timer(
        const Duration(milliseconds: 520),
        () => unawaited(_reopenForSettings()),
      );
    }
  }

  // ------------------------------------------------------------- navigation

  void _onPageChanged(int index) {
    setState(() {
      _pageIndex = index;
      _sliderValue = null;
    });
    _scheduleSave();
  }

  void _jumpTo(int page) {
    final engine = _engine;
    if (engine == null) return;
    setState(() {
      _pageIndex = page.clamp(0, math.max(0, engine.pageCount - 1));
      _sliderValue = null;
      _chromeVisible = true;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(_persistProgress()),
    );
  }

  Future<void> _persistProgress() async {
    final engine = _engine;
    if (engine == null || engine.pageCount <= 0) return;
    final page = _pageIndex.clamp(0, engine.pageCount - 1);
    final current = _library.bookById(widget.book.id) ?? widget.book;
    await _library.saveProgress(
      current,
      position: engine.positionForPage(page),
      pageCount: engine.pageCount,
      progress: engine.progressForPage(page),
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _saveTimer?.cancel();
    _settingsTimer?.cancel();
    await _persistProgress();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // -------------------------------------------------------------- bookmarks

  Future<void> _loadBookmarks() async {
    try {
      final list = await _library.bookmarksFor(widget.book.id);
      if (!mounted) return;
      setState(() => _bookmarks = list);
    } catch (_) {
      // Bookmarks are a convenience; the book still reads fine without them.
    }
  }

  Bookmark? get _bookmarkHere {
    final engine = _engine;
    for (final bookmark in _bookmarks) {
      if (bookmark.page == _pageIndex) return bookmark;
      if (engine == null) continue;
      final resolved = engine.pageForPosition(
        ReadingPosition(
          chapter: bookmark.chapter,
          page: bookmark.page,
          offset: bookmark.offset,
        ),
      );
      if (resolved == _pageIndex) return bookmark;
    }
    return null;
  }

  Future<void> _toggleBookmark() async {
    final engine = _engine;
    if (engine == null) return;
    final existing = _bookmarkHere;

    if (existing != null) {
      await _library.deleteBookmark(existing.id);
      if (!mounted) return;
      setState(() {
        _bookmarks = _bookmarks
            .where((bookmark) => bookmark.id != existing.id)
            .toList();
      });
      showToast(context, 'Bookmark removed.');
      return;
    }

    final bookmark = await _library.addBookmark(
      book: widget.book,
      position: engine.positionForPage(_pageIndex),
      snippet: truncate(engine.snippetForPage(_pageIndex), 140),
    );
    if (!mounted) return;
    setState(() => _bookmarks = [bookmark, ..._bookmarks]);
    showToast(context, 'Bookmarked page ${_pageIndex + 1}.');
  }

  Future<void> _openBookmarks() async {
    final selected = await showBookmarksSheet(
      context,
      book: widget.book,
      repo: _library,
      onChanged: () => unawaited(_loadBookmarks()),
    );
    if (selected == null || !mounted) return;
    final engine = _engine;
    if (engine == null) return;
    _jumpTo(
      engine.pageForPosition(
        ReadingPosition(
          chapter: selected.chapter,
          page: selected.page,
          offset: selected.offset,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _openToc() async {
    final engine = _engine;
    if (engine == null) return;
    final page = await showTocSheet(
      context,
      entries: engine.toc,
      currentPage: _pageIndex,
    );
    if (page != null && mounted) _jumpTo(page);
  }

  Future<void> _openSearch() async {
    final engine = _engine;
    if (engine == null) return;
    final page = await showSearchSheet(
      context,
      engine: engine,
      enabled: widget.book.isEpub,
    );
    if (page != null && mounted) _jumpTo(page);
  }

  Future<void> _openSettings() async {
    await showReaderSettingsSheet(context, _settings, _applySettings);
  }

  Future<void> _openJump() async {
    final engine = _engine;
    if (engine == null) return;
    final page = await showPageJumpDialog(
      context,
      pageCount: engine.pageCount,
      currentPage: _pageIndex,
    );
    if (page != null && mounted) _jumpTo(page);
  }

  Future<void> _openZoom() async {
    final engine = _engine;
    if (engine is! PdfReaderEngine) return;
    await showPdfZoom(context, engine: engine, pageIndex: _pageIndex);
  }

  Future<void> _setCoverFromCurrentPage() async {
    final engine = _engine;
    if (engine == null) return;
    final currentBook = _library.bookById(widget.book.id) ?? widget.book;

    if (currentBook.isPdf) {
      try {
        final doc = await PdfDocument.openFile(currentBook.filePath);
        try {
          final page = await doc.getPage(_pageIndex + 1);
          try {
            final ratio = page.width <= 0 ? 1.5 : page.height / page.width;
            final rendered = await page.render(
              width: 900,
              height: 900 * ratio,
              format: PdfPageImageFormat.jpeg,
              quality: 88,
            );
            if (rendered != null) {
              final ok = await _library.setCoverFromBytes(currentBook, rendered.bytes);
              if (mounted) {
                showToast(
                  context,
                  ok ? 'Page ${_pageIndex + 1} set as book cover!' : 'Could not save cover.',
                );
              }
            }
          } finally {
            await page.close();
          }
        } finally {
          await doc.close();
        }
      } catch (e) {
        if (mounted) showToast(context, 'Could not capture page: $e');
      }
    } else {
      showToast(context, 'Use "Choose a cover" in the shelf options for EPUB covers.');
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final palette = _settings.palette;
    final insets = MediaQuery.paddingOf(context);
    final engine = _engine;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: palette.page,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (engine == null)
              _loading
                  ? _LoadingView(
                      palette: palette,
                      progress: _layoutProgress,
                      insets: insets,
                      onClose: _close,
                    )
                  : _ErrorView(
                      palette: palette,
                      message: _error ?? 'This book could not be opened.',
                      insets: insets,
                      onRetry: () => unawaited(_openEngine()),
                      onClose: _close,
                    )
            else
              BookPager(
                key: ObjectKey(engine),
                pageCount: engine.pageCount,
                pageIndex: _pageIndex.clamp(
                  0,
                  math.max(0, engine.pageCount - 1),
                ),
                turnStyle: _settings.turnStyle,
                onPageChanged: _onPageChanged,
                onTapCenter: () => setState(() => _chromeVisible = !_chromeVisible),
                itemBuilder: (context, index) {
                  return _ReaderPage(
                    book: widget.book,
                    engine: engine,
                    pageIndex: index,
                    settings: _settings,
                    safeInsets: insets,
                  );
                },
              ),
            if (engine != null && _settings.brightness > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: _settings.brightness),
                  ),
                ),
              ),
            if (engine != null)
              _ReaderChrome(
                visible: _chromeVisible,
                book: _library.bookById(widget.book.id) ?? widget.book,
                engine: engine,
                pageIndex: _pageIndex,
                palette: palette,
                insets: insets,
                sliderValue: _sliderValue,
                bookmarked: _bookmarkHere != null,
                onClose: _close,
                onToggleBookmark: _toggleBookmark,
                onToggleChrome: () =>
                    setState(() => _chromeVisible = !_chromeVisible),
                onSetCover: widget.book.isPdf ? _setCoverFromCurrentPage : null,
                onToc: _openToc,
                onSearch: _openSearch,
                onBookmarks: _openBookmarks,
                onSettings: _openSettings,
                onJump: _openJump,
                onZoom: widget.book.isEpub ? null : _openZoom,
                onSliderChanged: (value) =>
                    setState(() => _sliderValue = value),
                onSliderEnd: (value) {
                  setState(() => _sliderValue = null);
                  _jumpTo(value.round());
                },
              ),
            if (_refreshing)
              Positioned(
                top: insets.top + 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: AppColors.brass,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Laying out pages… ${(_layoutProgress * 100).round()}%',
                            style: const TextStyle(
                              color: Color(0xFFF3E8D2),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderPage extends StatelessWidget {
  const _ReaderPage({
    required this.book,
    required this.engine,
    required this.pageIndex,
    required this.settings,
    required this.safeInsets,
  });

  final Book book;
  final ReaderEngine engine;
  final int pageIndex;
  final ReaderSettings settings;
  final EdgeInsets safeInsets;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final showNumber = settings.showPageNumber &&
        engine.pageCount > 1 &&
        settings.margins >= 17;
    return ColoredBox(
      color: palette.page,
      child: Stack(
        fit: StackFit.expand,
        children: [
          engine.buildPage(context, pageIndex, settings, safeInsets),
          if (showNumber)
            Positioned(
              left: 0,
              right: 0,
              bottom: safeInsets.bottom + 2,
              child: IgnorePointer(
                child: Text(
                  '${pageIndex + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: book.isEpub
                        ? palette.muted
                        : const Color(0xFF6B5B48).withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderChrome extends StatelessWidget {
  const _ReaderChrome({
    required this.visible,
    required this.book,
    required this.engine,
    required this.pageIndex,
    required this.palette,
    required this.insets,
    required this.sliderValue,
    required this.bookmarked,
    required this.onClose,
    required this.onToggleBookmark,
    required this.onToggleChrome,
    this.onSetCover,
    required this.onToc,
    required this.onSearch,
    required this.onBookmarks,
    required this.onSettings,
    required this.onJump,
    required this.onZoom,
    required this.onSliderChanged,
    required this.onSliderEnd,
  });

  final bool visible;
  final Book book;
  final ReaderEngine engine;
  final int pageIndex;
  final ReaderPalette palette;
  final EdgeInsets insets;
  final double? sliderValue;
  final bool bookmarked;
  final VoidCallback onClose;
  final VoidCallback onToggleBookmark;
  final VoidCallback onToggleChrome;
  final VoidCallback? onSetCover;
  final VoidCallback onToc;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;
  final VoidCallback onJump;
  final VoidCallback? onZoom;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderEnd;

  static const Color _cream = Color(0xFFF6EBD8);
  static const Color _creamSoft = Color(0xFFE3D2B3);

  @override
  Widget build(BuildContext context) {
    final chapter = engine.chapterTitleFor(pageIndex);
    final subtitle = chapter.trim().isNotEmpty
        ? chapter
        : (book.author.trim().isNotEmpty ? book.author : book.format.label);
    final total = engine.pageCount;
    final maxPage = math.max(1, total - 1).toDouble();
    final value = (sliderValue ?? pageIndex.toDouble()).clamp(0.0, maxPage);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.82),
                      Colors.black.withValues(alpha: 0.42),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.62, 1],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(4, insets.top + 4, 4, 28),
                child: Row(
                  children: [
                    _ChromeIcon(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back to library',
                      onTap: onClose,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggleChrome,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: serifStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _cream,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  letterSpacing: 0.25,
                                  color: _creamSoft.withValues(alpha: 0.75),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (onSetCover != null)
                      _ChromeIcon(
                        icon: Icons.photo_size_select_actual_outlined,
                        tooltip: 'Use this page as cover',
                        color: _cream,
                        onTap: onSetCover!,
                      ),
                    _ChromeIcon(
                      icon: bookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark page',
                      color: bookmarked ? AppColors.brass : _cream,
                      onTap: onToggleBookmark,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(12, 34, 12, insets.bottom + 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Text(
                            total > 0
                                ? 'Page ${pageIndex + 1} of $total'
                                : 'Page',
                            style: TextStyle(
                              fontSize: 11,
                              color: _creamSoft.withValues(alpha: 0.9),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            total > 0
                                ? formatPercent(
                                    engine.progressForPage(pageIndex),
                                  )
                                : '',
                            style: TextStyle(
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: _creamSoft.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.4,
                        activeTrackColor: AppColors.brass,
                        inactiveTrackColor:
                            Colors.white.withValues(alpha: 0.22),
                        thumbColor: _cream,
                        overlayColor: AppColors.brass.withValues(alpha: 0.16),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5.5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 15,
                        ),
                      ),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: maxPage,
                        divisions:
                            total > 1 ? math.min(total - 1, 500) : null,
                        onChanged: total > 1 ? onSliderChanged : null,
                        onChangeEnd: total > 1 ? onSliderEnd : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ChromeControl(
                          icon: Icons.format_list_bulleted_rounded,
                          label: 'Contents',
                          onTap: onToc,
                        ),
                        _ChromeControl(
                          icon: Icons.search_rounded,
                          label: 'Search',
                          onTap: onSearch,
                        ),
                        _ChromeControl(
                          icon: Icons.bookmarks_outlined,
                          label: 'Marks',
                          onTap: onBookmarks,
                        ),
                        _ChromeControl(
                          icon: Icons.text_fields_rounded,
                          label: 'Text',
                          onTap: onSettings,
                        ),
                        if (onZoom != null)
                          _ChromeControl(
                            icon: Icons.zoom_in_rounded,
                            label: 'Zoom',
                            onTap: onZoom!,
                          )
                        else
                          _ChromeControl(
                            icon: Icons.pin_drop_outlined,
                            label: 'Go to',
                            onTap: onJump,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChromeIcon extends StatelessWidget {
  const _ChromeIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 21, color: color ?? const Color(0xFFF6EBD8)),
          ),
        ),
      ),
    );
  }
}

class _ChromeControl extends StatelessWidget {
  const _ChromeControl({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF6EBD8);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: cream),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.2,
                  color: cream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({
    required this.palette,
    required this.progress,
    required this.insets,
    required this.onClose,
  });

  final ReaderPalette palette;
  final double progress;
  final EdgeInsets insets;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.page,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: AppColors.brass,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Opening book…',
                  style: serifStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                if (progress > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Laying out pages (${(progress * 100).round()}%)',
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 4,
            top: insets.top + 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 21,
                    color: palette.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.palette,
    required this.message,
    required this.insets,
    required this.onRetry,
    required this.onClose,
  });

  final ReaderPalette palette;
  final String message;
  final EdgeInsets insets;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.page,
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(34, 60, 34, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 42,
                    color: palette.muted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This book could not be opened',
                    textAlign: TextAlign.center,
                    style: serifStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    truncate(message, 320),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: palette.muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(onPressed: onClose, child: const Text('Back')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: insets.top + 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 21,
                    color: palette.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
