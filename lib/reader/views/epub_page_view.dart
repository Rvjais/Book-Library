import 'package:flutter/material.dart';

import '../../data/reader_settings.dart';
import '../pagination/paginator.dart';

/// Renders one already-paginated EPUB page.
class EpubPageView extends StatelessWidget {
  const EpubPageView({
    super.key,
    required this.page,
    required this.settings,
    this.safeInsets = EdgeInsets.zero,
  });

  final BookPage page;
  final ReaderSettings settings;
  final EdgeInsets safeInsets;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      settings.margins + safeInsets.left,
      settings.margins * 0.9 + safeInsets.top,
      settings.margins + safeInsets.right,
      settings.margins * 0.9 + safeInsets.bottom,
    );

    return Padding(
      padding: padding,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in page.items) _buildItem(item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(PageItem item) {
    if (item is PageTextItem) {
      return Padding(
        padding: EdgeInsets.only(top: item.spacingBefore, left: item.indent),
        child: RichText(
          text: item.span,
          textAlign: item.align,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        ),
      );
    }

    if (item is PageImageItem) {
      return Padding(
        padding: EdgeInsets.only(top: item.spacingBefore),
        child: SizedBox(
          height: item.height,
          width: double.infinity,
          child: Image.memory(
            item.bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    if (item is PageRuleItem) {
      return Padding(
        padding: EdgeInsets.only(top: item.spacingBefore),
        child: SizedBox(
          height: settings.fontSize * 1.6,
          child: Center(
            child: Container(
              width: 64,
              height: 0.8,
              color: settings.palette.rule,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
