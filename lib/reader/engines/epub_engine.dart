import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import '../../data/reader_settings.dart';
import '../../epub/epub_models.dart';
import '../../epub/epub_parser.dart';
import '../pagination/paginator.dart';
import '../views/epub_page_view.dart';
import 'reader_engine.dart';

/// Parses an EPUB and paginates it for the current screen + typography.
class EpubReaderEngine implements ReaderEngine {
  EpubReaderEngine._(
    this.book,
    this.parsed,
    this._pages,
    this._chapterFirstPage,
    this.settings,
  );

  static Future<EpubReaderEngine> open(
    Book book,
    ReaderSettings settings,
    Size contentSize, {
    void Function(double progress)? onProgress,
  }) async {
    final parsed = await EpubParser.open(book.filePath);

    final paginator = Paginator(
      settings: settings,
      width: contentSize.width,
      height: contentSize.height,
    );

    final pages = <BookPage>[];
    final chapterFirstPage = <int, int>{};

    for (var index = 0; index < parsed.chapters.length; index++) {
      final chapter = parsed.chapters[index];
      chapterFirstPage[chapter.index] = pages.length;
      pages.addAll(paginator.paginateChapter(chapter));
      onProgress?.call((index + 1) / parsed.chapters.length);
      // Give the UI thread a chance to breathe every few chapters.
      if (index % 3 == 2) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (pages.isEmpty) {
      pages.add(
        BookPage(
          chapterIndex: 0,
          chapterTitle: parsed.title ?? book.title,
          startOffset: 0,
          endOffset: 1,
          items: const <PageItem>[],
        ),
      );
    }

    return EpubReaderEngine._(book, parsed, pages, chapterFirstPage, settings);
  }

  @override
  final Book book;
  final ParsedEpub parsed;
  final List<BookPage> _pages;
  final Map<int, int> _chapterFirstPage;
  final ReaderSettings settings;

  @override
  int get pageCount => _pages.length;

  @override
  List<ReaderTocEntry> get toc {
    return parsed.toc.map((entry) {
      return ReaderTocEntry(
        title: entry.title,
        pageIndex: _chapterFirstPage[entry.chapterIndex] ?? 0,
        level: entry.level,
      );
    }).toList(growable: false);
  }

  List<ReaderTocEntry> get chapters => parsed.toc
      .map(
        (entry) => ReaderTocEntry(
          title: entry.title,
          pageIndex: _chapterFirstPage[entry.chapterIndex] ?? 0,
          level: entry.level,
        ),
      )
      .toList(growable: false);

  @override
  String chapterTitleFor(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pages.length) return '';
    return _pages[pageIndex].chapterTitle;
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
    return EpubPageView(
      page: _pages[pageIndex],
      settings: settings,
      safeInsets: safeInsets,
      onTextHighlighted: onTextHighlighted,
      highlights: highlights,
    );
  }

  @override
  ReadingPosition positionForPage(int pageIndex) {
    final page = _pages[pageIndex.clamp(0, _pages.length - 1)];
    return ReadingPosition(
      chapter: page.chapterIndex,
      page: pageIndex,
      offset: page.startOffset,
    );
  }

  @override
  int pageForPosition(ReadingPosition position) {
    final first = _chapterFirstPage[position.chapter];
    if (first == null) {
      return position.page.clamp(0, _pages.length - 1);
    }

    for (var index = first; index < _pages.length; index++) {
      final page = _pages[index];
      if (page.chapterIndex != position.chapter) break;
      final isLastOfChapter = index + 1 >= _pages.length ||
          _pages[index + 1].chapterIndex != position.chapter;
      if (position.offset >= page.startOffset &&
          (position.offset < page.endOffset || isLastOfChapter)) {
        return index;
      }
    }
    return first;
  }

  @override
  double progressForPage(int pageIndex) {
    if (_pages.isEmpty) return 0;
    return ((pageIndex + 1) / _pages.length).clamp(0.0, 1.0);
  }

  @override
  String snippetForPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pages.length) return '';
    return _pages[pageIndex].previewText;
  }

  @override
  Future<List<ReaderSearchHit>> search(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.length < 2) return const <ReaderSearchHit>[];

    const limit = 60;
    final hits = <ReaderSearchHit>[];

    for (final chapter in parsed.chapters) {
      final text = chapter.plainText;
      final lower = text.toLowerCase();
      var from = 0;
      while (hits.length < limit) {
        final index = lower.indexOf(needle, from);
        if (index < 0) break;

        final start = math.max(0, index - 48);
        final end = math.min(text.length, index + needle.length + 72);
        final snippet = text
            .substring(start, end)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        final pageIndex = pageForPosition(
          ReadingPosition(chapter: chapter.index, offset: index),
        );
        hits.add(
          ReaderSearchHit(
            chapter: chapter.title,
            pageIndex: pageIndex,
            snippet: snippet,
          ),
        );
        from = index + needle.length;
      }
      if (hits.length >= limit) break;
    }
    return hits;
  }

  @override
  Future<void> dispose() async {
    // Parsed content is plain Dart data; the GC takes care of it.
  }
}
