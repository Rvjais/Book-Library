import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfPageView;

import '../../data/models.dart';
import '../../data/reader_settings.dart';
import '../views/pdf_page_view.dart';
import 'reader_engine.dart';

/// Renders PDF pages to bitmaps and extracts text with pdfrx / PDFium.
class PdfReaderEngine implements ReaderEngine {
  PdfReaderEngine._(this.book, this._document, this._renderWidth, this._toc);

  static Future<PdfReaderEngine> open(Book book, {double renderWidth = 1500}) async {
    final document = await PdfDocument.openFile(book.filePath);
    final toc = <ReaderTocEntry>[];
    try {
      final outline = await document.loadOutline();
      void addOutline(List<PdfOutlineNode> nodes, int level) {
        for (final node in nodes) {
          final pageNum = node.dest?.pageNumber;
          if (pageNum != null && pageNum >= 1) {
            toc.add(
              ReaderTocEntry(
                title: node.title.trim().isEmpty ? 'Chapter' : node.title.trim(),
                pageIndex: (pageNum - 1).clamp(0, document.pages.length - 1),
                level: level,
              ),
            );
          }
          if (node.children.isNotEmpty) {
            addOutline(node.children, level + 1);
          }
        }
      }
      addOutline(outline, 0);
    } catch (_) {
      // PDF might not have outline
    }
    return PdfReaderEngine._(book, document, renderWidth, toc);
  }

  @override
  final Book book;
  final PdfDocument _document;
  final double _renderWidth;
  final List<ReaderTocEntry> _toc;

  final LinkedHashMap<int, ui.Image> _cache = LinkedHashMap<int, ui.Image>();
  final Map<int, Future<ui.Image>> _pending = {};
  final List<int> _recent = <int>[];
  final Map<int, PdfPageText> _textCache = {};

  bool _disposed = false;

  PdfDocument get document => _document;

  PdfPage pageAt(int pageIndex) => _document.pages[pageIndex];

  Future<PdfPageText?> loadTextFor(int pageIndex) async {
    if (_disposed || pageIndex < 0 || pageIndex >= pageCount) return null;
    if (_textCache.containsKey(pageIndex)) return _textCache[pageIndex];
    try {
      final page = _document.pages[pageIndex];
      final text = await page.loadStructuredText();
      _textCache[pageIndex] = text;
      return text;
    } catch (_) {
      return null;
    }
  }

  @override
  int get pageCount => _document.pages.length;

  @override
  List<ReaderTocEntry> get toc => _toc;

  @override
  String chapterTitleFor(int pageIndex) {
    ReaderTocEntry? match;
    for (final entry in _toc) {
      if (entry.pageIndex <= pageIndex) {
        if (match == null || entry.pageIndex > match.pageIndex) {
          match = entry;
        }
      }
    }
    return match?.title ?? 'Page ${pageIndex + 1}';
  }

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex,
    ReaderSettings settings,
    EdgeInsets safeInsets, {
    ValueChanged<SelectedText>? onTextHighlighted,
    List<BookHighlight> highlights = const <BookHighlight>[],
    ValueChanged<bool>? onZoomChanged,
  }) {
    return PdfPageView(
      engine: this,
      pageIndex: pageIndex,
      settings: settings,
      safeInsets: safeInsets,
      onTextHighlighted: onTextHighlighted,
      highlights: highlights,
      onZoomChanged: onZoomChanged,
    );
  }

  @override
  ReadingPosition positionForPage(int pageIndex) =>
      ReadingPosition(page: pageIndex, chapter: 0, offset: 0);

  @override
  int pageForPosition(ReadingPosition position) =>
      position.page.clamp(0, math.max(0, pageCount - 1));

  @override
  double progressForPage(int pageIndex) =>
      pageCount <= 0 ? 0 : (pageIndex + 1) / pageCount;

  @override
  String snippetForPage(int pageIndex) => 'Page ${pageIndex + 1}';

  @override
  Future<List<ReaderSearchHit>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const <ReaderSearchHit>[];
    final qLower = q.toLowerCase();
    final hits = <ReaderSearchHit>[];
    for (var i = 0; i < _document.pages.length; i++) {
      if (_disposed) break;
      try {
        final page = _document.pages[i];
        final rawText = await page.loadText();
        if (rawText == null || rawText.fullText.isEmpty) continue;
        final text = rawText.fullText;
        final textLower = text.toLowerCase();
        var startIndex = 0;
        while (true) {
          final index = textLower.indexOf(qLower, startIndex);
          if (index < 0) break;
          final snippetStart = math.max(0, index - 30);
          final snippetEnd = math.min(text.length, index + q.length + 30);
          final snippet =
              text.substring(snippetStart, snippetEnd).replaceAll('\n', ' ').trim();
          hits.add(ReaderSearchHit(
            chapter: chapterTitleFor(i),
            pageIndex: i,
            snippet: '...$snippet...',
          ));
          startIndex = index + q.length;
          if (hits.length >= 100) break;
        }
      } catch (_) {}
      if (hits.length >= 100) break;
    }
    return hits;
  }

  /// Synchronously returns a cached rendered image if already available.
  ui.Image? cachedImageFor(int pageIndex) {
    final cached = _cache[pageIndex];
    if (cached != null) {
      _touch(pageIndex);
    }
    return cached;
  }

  /// Returns a rendered page, caching a generous buffer of pages for smooth turning.
  Future<ui.Image> imageFor(int pageIndex) {
    final cached = _cache.remove(pageIndex);
    if (cached != null) {
      _cache[pageIndex] = cached;
      _touch(pageIndex);
      return Future<ui.Image>.value(cached);
    }

    final pending = _pending[pageIndex];
    if (pending != null) return pending;

    final future = _render(pageIndex);
    _pending[pageIndex] = future;
    return future.then((image) {
      _pending.remove(pageIndex);
      if (_disposed) {
        image.dispose();
        return image;
      }
      _cache[pageIndex] = image;
      _touch(pageIndex);
      _trim();
      return image;
    }).catchError((Object error) {
      _pending.remove(pageIndex);
      throw error;
    });
  }

  void _touch(int index) {
    _recent.remove(index);
    _recent.insert(0, index);
    if (_recent.length > 8) {
      _recent.removeRange(8, _recent.length);
    }
  }

  void _trim() {
    // Keep 8 pages in cache so turning back and forth doesn't re-render
    while (_cache.length > 8) {
      int? victim;
      for (final key in _cache.keys) {
        if (!_recent.contains(key)) {
          victim = key;
          break;
        }
      }
      if (victim == null) break;
      final image = _cache.remove(victim);
      image?.dispose();
    }
  }

  Future<ui.Image> _render(int pageIndex) async {
    if (_disposed) throw StateError('The PDF has been closed.');
    if (pageIndex < 0 || pageIndex >= _document.pages.length) {
      throw RangeError.index(pageIndex, _document.pages);
    }
    final page = _document.pages[pageIndex];
    final ratio = page.width <= 0 ? 1.4 : page.height / page.width;
    final targetWidth = math.max(720.0, _renderWidth);
    final targetHeight = targetWidth * ratio;
    final pdfImage = await page.render(
      width: targetWidth.round(),
      height: targetHeight.round(),
    );
    if (pdfImage == null) {
      throw StateError('Could not render page ${pageIndex + 1}.');
    }
    final image = await pdfImage.createImage();
    pdfImage.dispose();
    return image;
  }

  /// Warm up neighbouring pages so the next turn is instant.
  void prefetch(int pageIndex) {
    if (_disposed) return;
    final next = pageIndex + 1;
    final previous = pageIndex - 1;
    if (next < pageCount && !_cache.containsKey(next) && !_pending.containsKey(next)) {
      unawaited(_prefetchQuietly(next));
    }
    if (previous >= 0 &&
        !_cache.containsKey(previous) &&
        !_pending.containsKey(previous)) {
      unawaited(_prefetchQuietly(previous));
    }
  }

  Future<void> _prefetchQuietly(int index) async {
    try {
      await imageFor(index);
    } catch (_) {
      // Prefetching is best-effort.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final pending = _pending.values.toList(growable: false);
    for (final future in pending) {
      try {
        await future;
      } catch (_) {
        // A failed render is irrelevant once the book is being closed.
      }
    }
    _pending.clear();

    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _recent.clear();
    _textCache.clear();
    await _document.dispose();
  }
}
