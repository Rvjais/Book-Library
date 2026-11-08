import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:libready/data/models.dart';
import 'package:libready/data/reader_settings.dart';
import 'package:libready/epub/epub_models.dart';
import 'package:libready/reader/engines/reader_engine.dart';
import 'package:libready/reader/pagination/paginator.dart';
import 'package:libready/reader/views/epub_page_view.dart';
import 'package:libready/reader/widgets/book_pager.dart';

void main() {
  group('paginator', () {
    test('text spans carry no baked colour and keep chapter offsets', () {
      const plain = 'Hello world. This is a test of character offsets.';
      const chapter = EpubChapter(
        index: 3,
        path: 'c.xhtml',
        href: 'c.xhtml',
        title: 'Chapter',
        blocks: [
          RawTextBlock(
            runs: [RawRun(plain)],
            kind: BlockKind.paragraph,
            offset: 0,
          ),
        ],
        plainText: plain,
      );

      final paginator = Paginator(
        settings: const ReaderSettings(theme: ReaderTheme.black),
        width: 600,
        height: 800,
      );
      final pages = paginator.paginateChapter(chapter);
      expect(pages, isNotEmpty);

      for (final page in pages) {
        for (final item in page.items.whereType<PageTextItem>()) {
          // The colour must not be frozen into the paginated span.
          expect(item.span.style?.color, isNull);
          final text = item.span.toPlainText();
          expect(item.charLength, text.length);
          expect(
            plain.substring(
              item.chapterStart,
              item.chapterStart + item.charLength,
            ),
            text,
          );
        }
      }
    });
  });

  group('highlight anchors', () {
    test('round-trip through a database row', () {
      const highlight = BookHighlight(
        id: 1,
        bookId: 2,
        page: 5,
        chapter: 3,
        chapterOffset: 42,
        length: 7,
        text: 'anchor!',
        note: '',
        color: 0xFFFFEB3B,
        createdAt: 0,
      );

      final row = highlight.toRow();
      expect(row['chapter_offset'], 42);
      expect(row['length'], 7);

      final restored = BookHighlight.fromRow({...row, 'id': 1});
      expect(restored.chapterOffset, 42);
      expect(restored.length, 7);
      expect(restored.hasAnchor, isTrue);
      expect(restored.position.offset, 42);
      expect(restored.position.chapter, 3);
    });
  });

  group('EpubPageView', () {
    const page = BookPage(
      chapterIndex: 0,
      chapterTitle: 'Chapter',
      startOffset: 0,
      endOffset: 5,
      items: [
        PageTextItem(
          span: TextSpan(text: 'Hello'),
          spacingBefore: 0,
          align: TextAlign.start,
          indent: 0,
          chapterStart: 0,
          charLength: 5,
        ),
      ],
    );

    testWidgets('text colour follows the theme without re-pagination', (
      tester,
    ) async {
      Future<void> pump(ReaderTheme theme) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EpubPageView(
                page: page,
                settings: ReaderSettings(theme: theme),
              ),
            ),
          ),
        );
      }

      await pump(ReaderTheme.light);
      var text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.style?.color, paletteFor(ReaderTheme.light).text);

      // Same BookPage instance: the colour is resolved at paint time.
      await pump(ReaderTheme.dark);
      text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.style?.color, paletteFor(ReaderTheme.dark).text);
    });

    testWidgets('accepts anchored highlights without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpubPageView(
              page: page,
              settings: ReaderSettings(),
              highlights: [
                BookHighlight(
                  id: 1,
                  bookId: 1,
                  page: 0,
                  chapter: 0,
                  chapterOffset: 0,
                  length: 5,
                  text: 'Hello',
                  note: '',
                  color: 0xFFFFEB3B,
                  createdAt: 0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('long-press selection still works under the tap layer', (
      tester,
    ) async {
      SelectedText? selected;
      const selectable = BookPage(
        chapterIndex: 0,
        chapterTitle: 'Chapter',
        startOffset: 0,
        endOffset: 35,
        items: [
          PageTextItem(
            span: TextSpan(text: 'Hello brave new world of reading'),
            spacingBefore: 0,
            align: TextAlign.start,
            indent: 0,
            chapterStart: 0,
            charLength: 35,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookPager(
              pageCount: 1,
              pageIndex: 0,
              turnStyle: PageTurnStyle.none,
              onPageChanged: (_) {},
              itemBuilder: (context, index) => EpubPageView(
                page: selectable,
                settings: const ReaderSettings(),
                onTextHighlighted: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.longPress(find.byType(SelectableText));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Highlight'), findsOneWidget);

      await tester.tap(find.text('Highlight'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected, isNotNull);
      expect(selected!.text, isNotEmpty);
      expect(selected!.chapter, 0);
    });
  });
}
