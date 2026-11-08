import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/reader_settings.dart';
import '../../epub/epub_models.dart';

sealed class PageItem {
  const PageItem({required this.spacingBefore});
  final double spacingBefore;
}

class PageTextItem extends PageItem {
  const PageTextItem({
    required this.span,
    required super.spacingBefore,
    required this.align,
    required this.indent,
    required this.chapterStart,
    required this.charLength,
  });

  final TextSpan span;
  final TextAlign align;
  final double indent;

  /// Character offset (inside the chapter) of this item's first character.
  /// Used to anchor bookmarks and highlights so they survive re-pagination.
  final int chapterStart;

  /// Number of characters in [span].
  final int charLength;
}

class PageImageItem extends PageItem {
  const PageImageItem({
    required this.bytes,
    required this.height,
    required super.spacingBefore,
  });

  final Uint8List bytes;
  final double height;
}

class PageRuleItem extends PageItem {
  const PageRuleItem({required super.spacingBefore});
}

class BookPage {
  const BookPage({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.startOffset,
    required this.endOffset,
    required this.items,
  });

  final int chapterIndex;
  final String chapterTitle;

  /// Range of chapter text covered by this page (used to restore position
  /// after the book is re-paginated at a different font size).
  final int startOffset;
  final int endOffset;
  final List<PageItem> items;

  bool get isEmpty => items.isEmpty;

  String get previewText {
    final buffer = StringBuffer();
    for (final item in items) {
      if (item is PageTextItem) {
        buffer.write(item.span.toPlainText());
        buffer.write(' ');
      }
      if (buffer.length > 160) break;
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Lays a stream of EPUB blocks out into fixed-size pages using Flutter's own
/// text engine, so the rendered page always matches what was measured.
class Paginator {
  Paginator({
    required this.settings,
    required this.width,
    required this.height,
  });

  /// Sentinel colour used for link runs. The page view swaps it for the
  /// palette accent at paint time, so links follow the active theme.
  static const Color linkColor = Color(0xFF00FF01);

  final ReaderSettings settings;
  final double width;
  final double height;

  List<BookPage> paginateChapters(List<EpubChapter> chapters) {
    final pages = <BookPage>[];
    for (final chapter in chapters) {
      pages.addAll(paginateChapter(chapter));
      if (pages.length > 12000) break; // sanity guard
    }
    if (pages.isEmpty) {
      pages.add(
        BookPage(
          chapterIndex: 0,
          chapterTitle: chapters.isEmpty ? '' : chapters.first.title,
          startOffset: 0,
          endOffset: 1,
          items: const <PageItem>[],
        ),
      );
    }
    return pages;
  }

  List<BookPage> paginateChapter(EpubChapter chapter) {
    final pages = <BookPage>[];
    _PageDraft draft = _PageDraft(chapter.index, chapter.title, 0);
    var cursor = 0;
    var pendingAfter = 0.0;

    void finishPage(int endOffset) {
      if (draft.items.isEmpty) return;
      pages.add(
        draft.build(
          math.max(
            endOffset,
            draft.startOffset + 1,
          ),
        ),
      );
    }

    void newPage(int startOffset) {
      finishPage(startOffset);
      draft = _PageDraft(chapter.index, chapter.title, startOffset);
      pendingAfter = 0;
    }

    for (final block in chapter.blocks) {
      if (block is RawTextBlock) {
        cursor = block.offset;
        final metrics = _metricsFor(block.kind);
        final baseStyle = settings
            .layoutTextStyle(
              scale: metrics.scale,
              weight: metrics.bold ? FontWeight.w700 : null,
            )
            .copyWith(height: metrics.bold ? math.min(settings.lineHeight, 1.35) : settings.lineHeight);

        var consumed = 0;
        var firstFragment = true;
        final textLength = block.text.length;

        while (consumed < textLength) {
          final indent = metrics.indent * settings.fontSize;
          final availableWidth = math.max(40.0, width - indent);
          final before = firstFragment
              ? math.max(metrics.spacingBefore * settings.fontSize, pendingAfter)
              : 0.0;
          final availableHeight = height - draft.used - (draft.items.isEmpty ? 0 : before);

          final remaining = _spans(block.runs, consumed, textLength, baseStyle);
          final remainingPainter = TextPainter(
            text: TextSpan(style: baseStyle, children: remaining),
            textAlign: settings.textAlign,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout(maxWidth: availableWidth);
          final lines = remainingPainter.computeLineMetrics();
          if (lines.isEmpty) break;

          var fittedHeight = 0.0;
          var fit = 0;
          for (final line in lines) {
            if (fittedHeight + line.height > availableHeight + 0.5) break;
            fittedHeight += line.height;
            fit++;
          }

          if (fit == 0) {
            if (draft.items.isNotEmpty) {
              newPage(block.offset + consumed);
              continue;
            }
            fittedHeight = lines.first.height;
            fit = 1;
          }

          var endInBlock = textLength;
          if (fit < lines.length) {
            final position = remainingPainter.getPositionForOffset(
              Offset(availableWidth, math.max(0, fittedHeight - 0.5)),
            );
            endInBlock = consumed + position.offset;
          }
          if (endInBlock <= consumed) {
            endInBlock = math.min(textLength, consumed + 1);
          }

          final fragment = _spans(block.runs, consumed, endInBlock, baseStyle);
          final span = TextSpan(style: baseStyle, children: fragment);
          final fragmentPainter = TextPainter(
            text: span,
            textAlign: settings.textAlign,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout(maxWidth: availableWidth);

          if (draft.items.isNotEmpty &&
              draft.used + before + fragmentPainter.height > height + 0.5) {
            newPage(block.offset + consumed);
            continue;
          }

          draft.items.add(
            PageTextItem(
              span: span,
              spacingBefore: draft.items.isEmpty ? 0 : before,
              align: settings.textAlign,
              indent: indent,
              chapterStart: block.offset + consumed,
              charLength: endInBlock - consumed,
            ),
          );
          draft.used += (draft.items.length == 1 ? 0 : before) + fragmentPainter.height;

          consumed = endInBlock;
          cursor = block.offset + consumed;
          pendingAfter = metrics.spacingAfter * settings.fontSize;
          firstFragment = false;

          if (consumed < textLength) {
            newPage(block.offset + consumed);
          }
        }
        continue;
      }

      if (block is RawImageBlock) {
        final imageHeight = math.min(width / block.aspect, height * 0.92);
        final before = draft.items.isEmpty ? 0.0 : settings.fontSize * 0.85;
        if (draft.items.isNotEmpty && draft.used + before + imageHeight > height) {
          newPage(cursor);
        }
        draft.items.add(
          PageImageItem(
            bytes: block.bytes,
            height: imageHeight,
            spacingBefore: draft.items.isEmpty ? 0 : before,
          ),
        );
        draft.used += (draft.items.length == 1 ? 0 : before) + imageHeight;
        pendingAfter = settings.fontSize * 0.55;
        continue;
      }

      if (block is RawRuleBlock) {
        final before = draft.items.isEmpty ? 0.0 : settings.fontSize * 0.9;
        final ruleHeight = settings.fontSize * 1.6;
        if (draft.items.isNotEmpty && draft.used + before + ruleHeight > height) {
          newPage(cursor);
        }
        draft.items.add(
          PageRuleItem(spacingBefore: draft.items.isEmpty ? 0 : before),
        );
        draft.used += (draft.items.length == 1 ? 0 : before) + ruleHeight;
        pendingAfter = settings.fontSize * 0.9;
      }
    }

    if (draft.items.isNotEmpty) {
      finishPage(math.max(cursor, draft.startOffset + 1));
    }
    if (pages.isEmpty) {
      pages.add(
        BookPage(
          chapterIndex: chapter.index,
          chapterTitle: chapter.title,
          startOffset: 0,
          endOffset: 1,
          items: const <PageItem>[],
        ),
      );
    }
    return pages;
  }

  _BlockMetrics _metricsFor(BlockKind kind) {
    switch (kind) {
      case BlockKind.heading1:
        return const _BlockMetrics(scale: 1.5, bold: true, spacingBefore: 1.3, spacingAfter: 0.45);
      case BlockKind.heading2:
        return const _BlockMetrics(scale: 1.32, bold: true, spacingBefore: 1.15, spacingAfter: 0.4);
      case BlockKind.heading3:
        return const _BlockMetrics(scale: 1.18, bold: true, spacingBefore: 1.0, spacingAfter: 0.35);
      case BlockKind.heading4:
        return const _BlockMetrics(scale: 1.1, bold: true, spacingBefore: 0.9, spacingAfter: 0.3);
      case BlockKind.heading5:
      case BlockKind.heading6:
        return const _BlockMetrics(scale: 1.03, bold: true, spacingBefore: 0.8, spacingAfter: 0.3);
      case BlockKind.quote:
        return const _BlockMetrics(scale: 1.0, italic: true, spacingBefore: 0.6, spacingAfter: 0.4, indent: 0.9);
      case BlockKind.listItem:
        return const _BlockMetrics(scale: 1.0, spacingBefore: 0.28, spacingAfter: 0.1, indent: 0.8);
      case BlockKind.code:
        return const _BlockMetrics(scale: 0.86, monospace: true, spacingBefore: 0.6, spacingAfter: 0.4, indent: 0.7);
      case BlockKind.rule:
        return const _BlockMetrics(scale: 1.0, spacingBefore: 0.8, spacingAfter: 0.8);
      case BlockKind.paragraph:
        return const _BlockMetrics(scale: 1.0, spacingBefore: 0.55, spacingAfter: 0);
    }
  }

  TextStyle _runStyle(RawRun run, TextStyle base) {
    var style = base;
    if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
    if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (run.underline) {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    if (run.monospace) {
      style = style.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Courier New', 'monospace']);
    }
    if (run.link) {
      style = style.copyWith(
        color: Paginator.linkColor,
        decoration: TextDecoration.underline,
      );
    }
    return style;
  }

  List<InlineSpan> _spans(
    List<RawRun> runs,
    int start,
    int end,
    TextStyle base,
  ) {
    final output = <InlineSpan>[];
    var cursor = 0;
    for (final run in runs) {
      final runStart = cursor;
      final runEnd = cursor + run.text.length;
      cursor = runEnd;
      if (runEnd <= start) continue;
      if (runStart >= end) break;

      final from = math.max(start, runStart) - runStart;
      final to = math.min(end, runEnd) - runStart;
      if (to <= from) continue;

      final text = run.text.substring(from, to);
      if (text.isEmpty) continue;
      output.add(TextSpan(text: text, style: _runStyle(run, base)));
    }
    return output;
  }
}

class _BlockMetrics {
  const _BlockMetrics({
    required this.scale,
    this.bold = false,
    this.italic = false,
    this.monospace = false,
    this.spacingBefore = 0,
    this.spacingAfter = 0,
    this.indent = 0,
  });

  final double scale;
  final bool bold;
  final bool italic;
  final bool monospace;
  final double spacingBefore;
  final double spacingAfter;
  final double indent;
}

class _PageDraft {
  _PageDraft(this.chapterIndex, this.chapterTitle, this.startOffset);

  final int chapterIndex;
  final String chapterTitle;
  final int startOffset;
  final List<PageItem> items = [];
  double used = 0;

  BookPage build(int endOffset) => BookPage(
    chapterIndex: chapterIndex,
    chapterTitle: chapterTitle,
    startOffset: startOffset,
    endOffset: endOffset,
    items: List<PageItem>.unmodifiable(items),
  );
}
