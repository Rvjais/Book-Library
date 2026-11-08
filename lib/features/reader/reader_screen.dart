import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import '../../reader/views/zoomable_page.dart';
import '../../reader/widgets/book_pager.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/highlights_sheet.dart';
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

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late final LibraryRepository _library;
  late final SettingsRepository _settingsRepo;

  ReaderEngine? _engine;
  int _pageIndex = 0;
  bool _loading = true;
  bool _refreshing = false;
  double _layoutProgress = 0;
  String? _error;

  ReaderSettings _settings = const ReaderSettings();
  List<Bookmark> _bookmarks = const <Bookmark>[];
  List<BookHighlight> _highlights = const <BookHighlight>[];

  bool _chromeVisible = false;
  bool _zoomed = false;
  double? _sliderValue;

  Size? _openedSize;
  EdgeInsets? _openedInsets;
  int _generation = 0;

  Timer? _saveTimer;
  Timer? _settingsTimer;
  Timer? _settingsPersistTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library = context.read<LibraryRepository>();
    _settingsRepo = context.read<SettingsRepository>();
    _settings = _settingsRepo.reader;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);

    if (_openedSize == null) {
      unawaited(_openEngine());
      return;
    }

    if (_engine != null &&
        widget.book.isEpub &&
        (_openedSize != size || _openedInsets != insets)) {
      _reopenForLayout();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _settingsTimer?.cancel();
    _settingsPersistTimer?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Best-effort flush: the process can be killed without another frame,
      // so never rely on the debounce timer for the last position.
      _saveTimer?.cancel();
      _settingsPersistTimer?.cancel();
      unawaited(_persistProgress());
      unawaited(_settingsRepo.updateReader(_settings));
    }
  }

  /// Space the paginator may use. It must match the padding applied by
  /// [EpubPageView] exactly, or pages are measured larger than they can be
  /// drawn and the last line/image gets clipped at the bottom.
  Size _contentSize(Size screen, EdgeInsets insets) {
    final margins = _settings.margins;
    final width = screen.width - insets.horizontal - margins * 2;
    // EpubPageView uses 0.9 * margins above and below the text.
    final height = screen.height - insets.vertical - margins * 0.9 * 2;
    return Size(math.max(160.0, width), math.max(220.0, height));
  }

  Future<void> _loadBookmarks() async {
    final results = await _library.bookmarksFor(widget.book.id);
    final highResults = await _library.highlightsFor(widget.book.id);
    if (!mounted) return;
    setState(() {
      _bookmarks = results;
      _highlights = highResults;
    });
  }

  Bookmark? get _bookmarkHere {
    final engine = _engine;
    if (engine == null) return null;
    for (final bookmark in _bookmarks) {
      if (engine.pageForPosition(bookmark.position) == _pageIndex) {
        return bookmark;
      }
    }
    return null;
  }

  bool get _hasHighlightHere {
    final engine = _engine;
    if (engine == null) return false;
    return _highlights.any((h) => _pageForHighlight(engine, h) == _pageIndex);
  }

  /// Resolves an anchored highlight to its page; legacy rows fall back to the
  /// page they were saved on.
  int _pageForHighlight(ReaderEngine engine, BookHighlight highlight) {
    if (!highlight.hasAnchor) return highlight.page;
    return engine.pageForPosition(highlight.position);
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
        _zoomed = false;
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

    // Sliders fire on every tick; coalesce the SharedPreferences writes.
    _settingsPersistTimer?.cancel();
    _settingsPersistTimer = Timer(
      const Duration(milliseconds: 320),
      () => unawaited(_settingsRepo.updateReader(value)),
    );

    // Theme, texture and brightness are resolved at paint time, so only
    // typography changes require a re-pagination pass.
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
      _zoomed = false;
      _sliderValue = null;
    });
    _scheduleSave();
  }

  void _jumpTo(int page) {
    final engine = _engine;
    if (engine == null) return;
    setState(() {
      _pageIndex = page.clamp(0, math.max(0, engine.pageCount - 1));
      _zoomed = false;
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
    _settingsPersistTimer?.cancel();
    await _persistProgress();
    await _settingsRepo.updateReader(_settings);
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- bookmarks

  Future<void> _toggleBookmark() async {
    final engine = _engine;
    if (engine == null) return;

    final existing = _bookmarkHere;
    if (existing != null) {
      await _library.deleteBookmark(existing.id);
      if (!mounted) return;
      setState(() {
        _bookmarks = _bookmarks.where((b) => b.id != existing.id).toList();
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
    final engine = _engine;
    if (engine == null) return;
    final selected = await showBookmarksSheet(
      context,
      book: widget.book,
      repo: _library,
      onChanged: () => unawaited(_loadBookmarks()),
      pageFor: (bookmark) => engine.pageForPosition(bookmark.position),
    );
    if (selected == null || !mounted) return;
    _jumpTo(engine.pageForPosition(selected.position));
  }

  Future<void> _openHighlights() async {
    final engine = _engine;
    if (engine == null) return;
    final target = await showHighlightsSheet(
      context,
      book: widget.book,
      repo: _library,
      onChanged: () => unawaited(_loadBookmarks()),
      pageFor: (highlight) => _pageForHighlight(engine, highlight),
    );
    if (target != null && mounted) {
      _jumpTo(_pageForHighlight(engine, target));
    }
  }

  Future<void> _highlightSelectedText(SelectedText selection) async {
    final text = selection.text.trim();
    if (text.isEmpty) return;
    const defaultColor = 0xFFFFEB3B; // Yellow
    await _library.addHighlight(
      book: widget.book,
      page: _pageIndex,
      chapter: selection.chapter,
      chapterOffset: selection.offset,
      length: selection.length,
      text: text,
      color: defaultColor,
    );
    await _loadBookmarks();
    if (mounted) {
      showToast(context, 'Highlighted!');
    }
  }

  Future<void> _addHighlightPrompt() async {
    if (widget.book.isPdf) {
      await _showPdfUnsupported('Text highlighting');
      return;
    }
    final engine = _engine;
    if (engine == null) return;
    final controller = TextEditingController();
    int chosenColor = 0xFFFFEB3B;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colors = [
              0xFFFFEB3B, // Yellow
              0xFF81C784, // Green
              0xFF64B5F6, // Blue
              0xFFFF8A80, // Pink
              0xFFFFD54F, // Amber
            ];
            return AlertDialog(
              title: const Text('Highlight text'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Paste or type text to highlight on this page…',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final c in colors)
                        GestureDetector(
                          onTap: () => setDialogState(() => chosenColor = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: chosenColor == c
                                    ? Colors.black87
                                    : Colors.transparent,
                                width: 2.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogCtx).pop(controller.text.trim()),
                  child: const Text('Save Highlight'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (result != null && result.isNotEmpty) {
      final position = engine.positionForPage(_pageIndex);
      await _library.addHighlight(
        book: widget.book,
        page: _pageIndex,
        chapter: position.chapter,
        chapterOffset: position.offset,
        length: result.length,
        text: result,
        color: chosenColor,
      );
      await _loadBookmarks();
      if (mounted) showToast(context, 'Highlight saved!');
    }
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
      enabled: true,
    );
    if (page != null && mounted) _jumpTo(page);
  }

  /// PDF pages are fixed images, so text-only tools cannot work on them. Make
  /// the limitation explicit instead of opening an empty sheet.
  Future<void> _showPdfUnsupported(String feature) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.picture_as_pdf_outlined,
            size: 30,
            color: AppColors.brass,
          ),
          title: Text('$feature needs EPUB'),
          content: Text(
            "PDF books don't support this feature. Please use the EPUB format "
            'of the book to use it.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await showReaderSettingsSheet(
      context,
      _settings,
      _applySettings,
      isPdf: widget.book.isPdf,
    );
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
                theme: _settings.theme,
                texture: _settings.texture,
                onPageChanged: _onPageChanged,
                onTapCenter: () => setState(() => _chromeVisible = !_chromeVisible),
                gesturesEnabled: !_zoomed,
                pageReady: (index) =>
                    engine is! PdfReaderEngine ||
                    engine.cachedImageFor(index) != null,
                itemBuilder: (context, index) {
                  final pageHighlights = _highlights
                      .where((h) => _pageForHighlight(engine, h) == index)
                      .toList(growable: false);
                  return _ReaderPage(
                    key: ValueKey<int>(index),
                    book: widget.book,
                    engine: engine,
                    pageIndex: index,
                    settings: _settings,
                    safeInsets: insets,
                    onTextHighlighted: _highlightSelectedText,
                    highlights: pageHighlights,
                    onZoomChanged: (zoomed) {
                      if (_zoomed == zoomed) return;
                      setState(() => _zoomed = zoomed);
                    },
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
                hasHighlight: _hasHighlightHere,
                onClose: _close,
                onToggleBookmark: _toggleBookmark,
                onToggleChrome: () =>
                    setState(() => _chromeVisible = !_chromeVisible),
                onToc: _openToc,
                onSearch: _openSearch,
                onBookmarks: _openBookmarks,
                onHighlights: _openHighlights,
                onAddHighlight: _addHighlightPrompt,
                onSettings: _openSettings,
                onJump: _openJump,
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
    super.key,
    required this.book,
    required this.engine,
    required this.pageIndex,
    required this.settings,
    required this.safeInsets,
    this.onTextHighlighted,
    this.highlights = const <BookHighlight>[],
    this.onZoomChanged,
  });

  final Book book;
  final ReaderEngine engine;
  final int pageIndex;
  final ReaderSettings settings;
  final EdgeInsets safeInsets;
  final ValueChanged<SelectedText>? onTextHighlighted;
  final List<BookHighlight> highlights;
  final ValueChanged<bool>? onZoomChanged;

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
          if (engine is PdfReaderEngine)
            engine.buildPage(
              context,
              pageIndex,
              settings,
              safeInsets,
              onTextHighlighted: onTextHighlighted,
              highlights: highlights,
              onZoomChanged: onZoomChanged,
            )
          else
            // EPUB text is real Flutter text, so it can be magnified with a
            // transform instead of resizing the whole book.
            ZoomablePage(
              onZoomChanged: onZoomChanged,
              child: engine.buildPage(
                context,
                pageIndex,
                settings,
                safeInsets,
                onTextHighlighted: onTextHighlighted,
                highlights: highlights,
              ),
            ),
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
                    color: palette.muted,
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
    required this.hasHighlight,
    required this.onClose,
    required this.onToggleBookmark,
    required this.onToggleChrome,
    required this.onToc,
    required this.onSearch,
    required this.onBookmarks,
    required this.onHighlights,
    required this.onAddHighlight,
    required this.onSettings,
    required this.onJump,
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
  final bool hasHighlight;
  final VoidCallback onClose;
  final VoidCallback onToggleBookmark;
  final VoidCallback onToggleChrome;
  final VoidCallback onToc;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;
  final VoidCallback onHighlights;
  final VoidCallback onAddHighlight;
  final VoidCallback onSettings;
  final VoidCallback onJump;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderEnd;

  static const Color _cream = Color(0xFFF6EBD8);
  static const Color _creamSoft = Color(0xFFE3D2B3);

  @override
  Widget build(BuildContext context) {
    final isPdf = book.isPdf;
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
                      Colors.black.withValues(alpha: 0.52),
                      Colors.black.withValues(alpha: 0.86),
                    ],
                    stops: const [0, 0.38, 1],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(16, 26, 16, insets.bottom + 8),
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
                        if (!isPdf) ...[
                          Expanded(
                            child: _ChromeControl(
                              icon: Icons.format_list_bulleted_rounded,
                              label: 'Contents',
                              onTap: onToc,
                            ),
                          ),
                          Expanded(
                            child: _ChromeControl(
                              icon: Icons.search_rounded,
                              label: 'Search',
                              onTap: onSearch,
                            ),
                          ),
                          Expanded(
                            child: _ChromeControl(
                              icon: Icons.highlight_rounded,
                              label: 'Highlights',
                              onTap: onHighlights,
                            ),
                          ),
                        ],
                        Expanded(
                          child: _ChromeControl(
                            icon: Icons.bookmarks_outlined,
                            label: 'Marks',
                            onTap: onBookmarks,
                          ),
                        ),
                        Expanded(
                          child: _ChromeControl(
                            icon: Icons.tune_rounded,
                            label: 'Theme',
                            onTap: onSettings,
                          ),
                        ),
                        Expanded(
                          child: _ChromeControl(
                            icon: Icons.pin_drop_outlined,
                            label: 'Go to',
                            onTap: onJump,
                          ),
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
    this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Colors.white.withValues(alpha: 0.92);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: tint),
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
    const creamSoft = Color(0xFFE3D2B3);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: cream),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.0,
                  letterSpacing: 0.1,
                  color: creamSoft,
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
    return Stack(
      children: [
        Positioned(
          top: insets.top + 6,
          left: 6,
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: palette.text),
            onPressed: onClose,
          ),
        ),
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
      ],
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
    return Stack(
      children: [
        Positioned(
          top: insets.top + 6,
          left: 6,
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: palette.text),
            onPressed: onClose,
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 42,
                  color: palette.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not open this book',
                  style: serifStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: palette.muted),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
