import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/reader_settings.dart';
import '../engines/reader_engine.dart';
import '../pagination/paginator.dart';
import '../widgets/page_texture_painter.dart';

/// Renders one already-paginated EPUB page with text selection support for
/// highlights. Text colour and highlight backgrounds are resolved at paint
/// time, so changing the reader theme never needs a re-pagination pass.
class EpubPageView extends StatelessWidget {
  const EpubPageView({
    super.key,
    required this.page,
    required this.settings,
    this.safeInsets = EdgeInsets.zero,
    this.onTextHighlighted,
    this.highlights = const <BookHighlight>[],
  });

  final BookPage page;
  final ReaderSettings settings;
  final EdgeInsets safeInsets;
  final ValueChanged<SelectedText>? onTextHighlighted;
  final List<BookHighlight> highlights;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      settings.margins + safeInsets.left,
      settings.margins * 0.9 + safeInsets.top,
      settings.margins + safeInsets.right,
      settings.margins * 0.9 + safeInsets.bottom,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
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
        ),

        // Textured paper grain overlay
        if (settings.texture != PageTexture.none)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PageTexturePainter(
                  texture: settings.texture,
                  palette: settings.palette,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItem(PageItem item) {
    if (item is PageTextItem) {
      final palette = settings.palette;
      final span = _recolourLinks(item.span, palette);
      final decorated = _decorate(span, item);
      return Padding(
        padding: EdgeInsets.only(top: item.spacingBefore, left: item.indent),
        child: SelectableText.rich(
          decorated ?? span,
          style: TextStyle(color: palette.text),
          textAlign: item.align,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          contextMenuBuilder: (context, editableTextState) {
            final value = editableTextState.textEditingValue;
            final selection = value.selection;
            final raw = selection.textInside(value.text);
            final leading = raw.length - raw.trimLeft().length;
            final text = raw.trim();
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: [
                if (text.isNotEmpty && onTextHighlighted != null)
                  ContextMenuButtonItem(
                    label: 'Highlight',
                    onPressed: () {
                      onTextHighlighted?.call(
                        SelectedText(
                          text: text,
                          chapter: page.chapterIndex,
                          offset: item.chapterStart + selection.start + leading,
                        ),
                      );
                      editableTextState.hideToolbar();
                    },
                  ),
                ...editableTextState.contextMenuButtonItems,
              ],
            );
          },
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

  /// Swaps the paginator's link sentinel for the palette accent.
  TextSpan _recolourLinks(TextSpan span, ReaderPalette palette) {
    final children = span.children;
    return TextSpan(
      text: span.text,
      style: span.style?.color == Paginator.linkColor
          ? span.style!.copyWith(color: palette.accent)
          : span.style,
      children: children
          ?.map(
            (child) => child is TextSpan
                ? _recolourLinks(child, palette)
                : child,
          )
          .toList(growable: false),
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
    );
  }

  /// Rebuilds the item's spans with `backgroundColor` over the ranges that are
  /// covered by a highlight. Returns null when nothing on this item is
  /// highlighted, so the common case stays allocation-free.
  TextSpan? _decorate(TextSpan root, PageTextItem item) {
    final ranges = _rangesFor(item);
    if (ranges.isEmpty) return null;

    final output = <InlineSpan>[];
    var cursor = item.chapterStart;

    void visit(InlineSpan span, TextStyle? inherited) {
      if (span is! TextSpan) return;
      final style = inherited == null ? span.style : inherited.merge(span.style);
      final text = span.text;
      if (text != null && text.isNotEmpty) {
        final runStart = cursor;
        final runEnd = cursor + text.length;
        cursor = runEnd;

        var pos = runStart;
        while (pos < runEnd) {
          final active = ranges.where((r) => r.start <= pos && r.end > pos);
          var next = runEnd;
          if (active.isEmpty) {
            for (final range in ranges) {
              if (range.start > pos && range.start < next) next = range.start;
            }
          } else {
            for (final range in active) {
              if (range.end < next) next = range.end;
            }
          }
          final chunkEnd = next <= pos ? runEnd : next;
          final color = active.isEmpty ? null : active.last.color;
          output.add(
            TextSpan(
              text: text.substring(pos - runStart, chunkEnd - runStart),
              style: color == null
                  ? style
                  : (style ?? const TextStyle())
                        .copyWith(backgroundColor: color),
            ),
          );
          pos = chunkEnd;
        }
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }

    visit(root, null);
    return TextSpan(style: root.style, children: output);
  }

  List<_HighlightRange> _rangesFor(PageTextItem item) {
    final itemStart = item.chapterStart;
    final itemEnd = itemStart + item.charLength;
    final result = <_HighlightRange>[];
    for (final highlight in highlights) {
      if (highlight.chapter != page.chapterIndex) continue;
      if (highlight.hasAnchor) {
        if (highlight.chapterOffset < itemEnd &&
            highlight.chapterOffset + highlight.length > itemStart) {
          result.add(
            _HighlightRange(
              highlight.chapterOffset,
              highlight.chapterOffset + highlight.length,
              highlight.colorValue,
            ),
          );
        }
      } else if (highlight.text.isNotEmpty) {
        // Legacy rows saved before anchors existed: locate the text on the
        // page so they still render instead of silently disappearing.
        final at = item.span.toPlainText().indexOf(highlight.text);
        if (at >= 0) {
          result.add(
            _HighlightRange(
              itemStart + at,
              itemStart + at + highlight.text.length,
              highlight.colorValue,
            ),
          );
        }
      }
    }
    return result;
  }
}

class _HighlightRange {
  const _HighlightRange(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;
}
