import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:libready/data/reader_settings.dart';
import 'package:libready/reader/views/zoomable_page.dart';
import 'package:libready/reader/widgets/book_pager.dart';

Widget _pager({
  required Widget child,
  required int pageCount,
  required ValueChanged<int> onPageChanged,
  PageTurnStyle turnStyle = PageTurnStyle.none,
  VoidCallback? onTapCenter,
  bool gesturesEnabled = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BookPager(
        pageCount: pageCount,
        pageIndex: 0,
        turnStyle: turnStyle,
        gesturesEnabled: gesturesEnabled,
        onPageChanged: onPageChanged,
        onTapCenter: onTapCenter,
        itemBuilder: (context, index) => child,
      ),
    ),
  );
}

void main() {
  testWidgets('center tap toggles chrome even over SelectableText', (
    tester,
  ) async {
    var tapped = 0;
    var page = 0;
    await tester.pumpWidget(
      _pager(
        pageCount: 3,
        onPageChanged: (i) => page = i,
        onTapCenter: () => tapped++,
        child: const Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: SelectableText('Hello world selection text here'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tapped, 1, reason: 'tap layer must beat SelectableText');
    expect(page, 0);
  });

  testWidgets('horizontal swipe over text still turns the page', (tester) async {
    var page = 0;
    await tester.pumpWidget(
      _pager(
        pageCount: 3,
        onPageChanged: (i) => page = i,
        child: const ZoomablePage(
          child: Center(
            child: SizedBox(
              width: 340,
              height: 640,
              child: SelectableText(
                'The quick brown fox jumps over the lazy dog again and again.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 100));

    expect(page, 1, reason: 'selectable text must not swallow page swipes');
  });

  testWidgets('two-finger pinch reaches an InteractiveViewer child', (
    tester,
  ) async {
    final controller = TransformationController();
    var page = 0;
    await tester.pumpWidget(
      _pager(
        pageCount: 3,
        turnStyle: PageTurnStyle.curl,
        onPageChanged: (i) => page = i,
        child: InteractiveViewer(
          transformationController: controller,
          minScale: 1,
          maxScale: 4,
          child: const ColoredBox(color: Colors.amber),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final g1 = await tester.startGesture(const Offset(250, 300));
    final g2 = await tester.startGesture(const Offset(450, 300));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 6; i++) {
      await g1.moveBy(const Offset(-14, 0));
      await g2.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.05));
    expect(page, 0, reason: 'a pinch must not turn the page');
  });

  testWidgets('pinch over selectable text zooms the EPUB page', (tester) async {
    var page = 0;
    bool? zoomed;
    await tester.pumpWidget(
      _pager(
        pageCount: 3,
        turnStyle: PageTurnStyle.curl,
        onPageChanged: (i) => page = i,
        child: ZoomablePage(
          onZoomChanged: (value) => zoomed = value,
          child: const Center(
            child: SizedBox(
              width: 340,
              height: 640,
              child: SelectableText(
                'The quick brown fox jumps over the lazy dog again and again.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final g1 = await tester.startGesture(const Offset(250, 300));
    final g2 = await tester.startGesture(const Offset(450, 300));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 0; i < 6; i++) {
      await g1.moveBy(const Offset(-14, 0));
      await g2.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 50));

    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(ZoomablePage),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1.05));
    expect(zoomed, isTrue, reason: 'the reader must know the page is zoomed');
    expect(page, 0, reason: 'a pinch must not turn the page');
  });

  testWidgets('horizontal swipe turns the page over an InteractiveViewer', (
    tester,
  ) async {
    final controller = TransformationController();
    var page = 0;
    await tester.pumpWidget(
      _pager(
        pageCount: 3,
        onPageChanged: (i) => page = i,
        child: InteractiveViewer(
          transformationController: controller,
          minScale: 1,
          maxScale: 4,
          child: const ColoredBox(color: Colors.amber),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 100));

    expect(page, 1, reason: 'swipe must turn the page, not pan the image');
  });

  testWidgets('page turns are disabled while a page is zoomed', (tester) async {
    var page = 0;
    var tapped = 0;
    final controller = TransformationController();
    await tester.pumpWidget(
      _pager(
        pageCount: 3,
        gesturesEnabled: false,
        onPageChanged: (i) => page = i,
        onTapCenter: () => tapped++,
        child: InteractiveViewer(
          transformationController: controller,
          child: const ColoredBox(color: Colors.amber),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(page, 0);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tapped, 1, reason: 'chrome should still be reachable while zoomed');
  });
}
