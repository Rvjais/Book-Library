import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import '../../data/reader_settings.dart';

class ReaderTocEntry {
  const ReaderTocEntry({
    required this.title,
    required this.pageIndex,
    this.level = 0,
  });

  final String title;
  final int pageIndex;
  final int level;
}

class ReaderSearchHit {
  const ReaderSearchHit({
    required this.chapter,
    required this.pageIndex,
    required this.snippet,
  });

  final String chapter;
  final int pageIndex;
  final String snippet;
}

/// Common surface used by [ReaderScreen] for PDF and EPUB books.
abstract class ReaderEngine {
  Book get book;
  int get pageCount;
  List<ReaderTocEntry> get toc;

  String chapterTitleFor(int pageIndex);

  Widget buildPage(
    BuildContext context,
    int pageIndex,
    ReaderSettings settings,
    EdgeInsets safeInsets,
  );

  ReadingPosition positionForPage(int pageIndex);

  int pageForPosition(ReadingPosition position);

  double progressForPage(int pageIndex);

  String snippetForPage(int pageIndex);

  Future<List<ReaderSearchHit>> search(String query);

  Future<void> dispose();
}
