import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdfx/pdfx.dart';

import '../../data/models.dart';
import '../../data/reader_settings.dart';
import '../views/pdf_page_view.dart';
import 'reader_engine.dart';

/// Renders PDF pages to bitmaps with pdfx/PDFium.
class PdfReaderEngine implements ReaderEngine {
  PdfReaderEngine._(this.book, this._document, this._renderWidth);

  static Future<PdfReaderEngine> open(Book book, {double renderWidth = 1500}) async {
    final document = await PdfDocument.openFile(book.filePath);
    return PdfReaderEngine._(book, document, renderWidth);
  }

  @override
  final Book book;
  final PdfDocument _document;
  final double _renderWidth;

  final LinkedHashMap<int, ui.Image> _cache = LinkedHashMap<int, ui.Image>();
  final Map<int, Future<ui.Image>> _pending = {};
  final List<int> _recent = <int>[];

  bool _disposed = false;

  @override
  int get pageCount => _document.pagesCount;

  @override
  List<ReaderTocEntry> get toc => const <ReaderTocEntry>[];

  @override
  String chapterTitleFor(int pageIndex) => '';

  @override
  Widget buildPage(
    BuildContext context,
    int pageIndex,
    ReaderSettings settings,
    EdgeInsets safeInsets,
  ) {
    return PdfPageView(
      engine: this,
      pageIndex: pageIndex,
      safeInsets: safeInsets,
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
  Future<List<ReaderSearchHit>> search(String query) async =>
      const <ReaderSearchHit>[];

  /// Returns a rendered page, caching a handful of pages for smooth turning.
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
    if (_recent.length > 4) {
      _recent.removeRange(4, _recent.length);
    }
  }

  void _trim() {
    while (_cache.length > 4) {
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
    final page = await _document.getPage(pageIndex + 1);
    try {
      final ratio = page.width <= 0 ? 1.4 : page.height / page.width;
      final targetWidth = math.max(720.0, _renderWidth);
      final rendered = await page.render(
        width: targetWidth,
        height: targetWidth * ratio,
        format: PdfPageImageFormat.jpeg,
        quality: 88,
      );
      if (rendered == null) {
        throw StateError('Could not render page ${pageIndex + 1}.');
      }
      final codec = await ui.instantiateImageCodec(rendered.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } finally {
      await page.close();
    }
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
    _disposed = true;
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _recent.clear();
    await _document.close();
  }
}
