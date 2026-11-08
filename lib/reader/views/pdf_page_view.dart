import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfPageView;

import '../../data/models.dart';
import '../../data/reader_settings.dart';
import '../engines/pdf_engine.dart';
import '../engines/reader_engine.dart';
import '../widgets/page_texture_painter.dart';

class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.engine,
    required this.pageIndex,
    required this.settings,
    this.safeInsets = EdgeInsets.zero,
    this.onTextHighlighted,
    this.highlights = const <BookHighlight>[],
    this.onZoomChanged,
  });

  final PdfReaderEngine engine;
  final int pageIndex;
  final ReaderSettings settings;
  final EdgeInsets safeInsets;
  final ValueChanged<SelectedText>? onTextHighlighted;
  final List<BookHighlight> highlights;

  /// Fires when the page crosses between fit-to-screen and zoomed states, so
  /// the page-turn gestures can step aside and let the image pan.
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  Future<ui.Image>? _pendingImage;
  ui.Image? _loadedImage;
  PdfPageText? _pageText;

  final TransformationController _zoom = TransformationController();
  bool _zoomed = false;

  PdfPageTextRange? _selection;
  Offset? _toolbarGlobalPosition;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.engine != widget.engine) {
      _resetZoom();
      _clearSelection();
      _load();
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _clearSelection() {
    if (_selection != null || _toolbarGlobalPosition != null) {
      setState(() {
        _selection = null;
        _toolbarGlobalPosition = null;
      });
    }
  }

  void _resetZoom() {
    if (_zoom.value != Matrix4.identity()) {
      _zoom.value = Matrix4.identity();
    }
    _setZoomed(false);
  }

  void _setZoomed(bool value) {
    if (_zoomed == value) return;
    _zoomed = value;
    widget.onZoomChanged?.call(value);
  }

  void _reportZoom() {
    _setZoomed(_zoom.value.getMaxScaleOnAxis() > 1.02);
  }

  void _load() {
    final cached = widget.engine.cachedImageFor(widget.pageIndex);
    if (cached != null) {
      _loadedImage = cached;
      _pendingImage = null;
    } else {
      _loadedImage = null;
      final future = widget.engine.imageFor(widget.pageIndex);
      _pendingImage = future;
      future.then((image) {
        if (!mounted) return;
        if (widget.engine.cachedImageFor(widget.pageIndex) == image) {
          setState(() {
            _loadedImage = image;
            _pendingImage = null;
          });
        }
      }).catchError((_) {});
    }

    widget.engine.loadTextFor(widget.pageIndex).then((text) {
      if (!mounted) return;
      setState(() => _pageText = text);
    }).catchError((_) {});

    widget.engine.prefetch(widget.pageIndex);
  }

  static List<double> _themeMatrix(Color bg, Color fg) {
    final bgR = bg.r * 255.0;
    final bgG = bg.g * 255.0;
    final bgB = bg.b * 255.0;

    final fgR = fg.r * 255.0;
    final fgG = fg.g * 255.0;
    final fgB = fg.b * 255.0;

    final sr = (bgR - fgR) / 255.0;
    final sg = (bgG - fgG) / 255.0;
    final sb = (bgB - fgB) / 255.0;

    return <double>[
      sr, 0, 0, 0, fgR,
      0, sg, 0, 0, fgG,
      0, 0, sb, 0, fgB,
      0, 0, 0, 1, 0,
    ];
  }

  Widget _buildThemedImage(ui.Image image) {
    final raw = RawImage(
      image: image,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
    );

    final palette = widget.settings.palette;
    final theme = widget.settings.theme;

    switch (theme) {
      case ReaderTheme.light:
      case ReaderTheme.sepia:
      case ReaderTheme.dark:
      case ReaderTheme.black:
        final matrix = _themeMatrix(palette.page, palette.text);
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: raw,
        );
    }
  }

  Future<void> _onLongPressStart(LongPressStartDetails details, Rect pageRect) async {
    var text = _pageText;
    if (text == null) {
      text = await widget.engine.loadTextFor(widget.pageIndex);
      if (!mounted) return;
      if (text != null) {
        setState(() => _pageText = text);
      }
    }
    if (text == null || text.fragments.isEmpty) return;
    if (!pageRect.contains(details.localPosition)) return;

    final page = widget.engine.pageAt(widget.pageIndex);
    final pointInPage = details.localPosition - pageRect.topLeft;
    final pdfPoint = pointInPage.toPdfPoint(page: page, scaledPageSize: pageRect.size);

    PdfPageTextFragment? targetFragment;
    for (final f in text.fragments) {
      if (f.bounds.containsPoint(pdfPoint, margin: 8)) {
        targetFragment = f;
        break;
      }
    }
    targetFragment ??= text.fragments.cast<PdfPageTextFragment?>().firstWhere(
      (f) => f != null && f.bounds.distanceSquaredTo(pdfPoint) < 400,
      orElse: () => null,
    );

    if (targetFragment == null) return;

    int charInFrag = 0;
    double minDist = double.infinity;
    for (var i = 0; i < targetFragment.charRects.length; i++) {
      final d = targetFragment.charRects[i].distanceSquaredTo(pdfPoint);
      if (d < minDist) {
        minDist = d;
        charInFrag = i;
      }
    }

    final fragText = targetFragment.text;
    if (fragText.isEmpty) return;
    if (charInFrag >= fragText.length) charInFrag = fragText.length - 1;

    int wordStart = charInFrag;
    while (wordStart > 0 && !RegExp(r'\s').hasMatch(fragText[wordStart - 1])) {
      wordStart--;
    }
    int wordEnd = charInFrag;
    while (wordEnd < fragText.length && !RegExp(r'\s').hasMatch(fragText[wordEnd])) {
      wordEnd++;
    }

    final startChar = wordStart < wordEnd ? wordStart : charInFrag;
    final endChar = wordStart < wordEnd ? wordEnd : math.min(charInFrag + 1, fragText.length);
    final start = targetFragment.index + startChar;
    final end = targetFragment.index + endChar;
    if (start < end) {
      final sel = PdfPageTextRange(
        pageText: text,
        start: start.clamp(0, text.fullText.length),
        end: end.clamp(0, text.fullText.length),
      );
      setState(() {
        _selection = sel;
        _toolbarGlobalPosition = details.globalPosition;
      });
    }
  }

  int _findClosestCharIndex(Offset localPos, Rect pageRect) {
    final text = _pageText;
    if (text == null || text.charRects.isEmpty) return 0;
    final page = widget.engine.pageAt(widget.pageIndex);
    final pointInPage = localPos - pageRect.topLeft;
    final pdfPoint = pointInPage.toPdfPoint(page: page, scaledPageSize: pageRect.size);

    int closest = 0;
    double minDist = double.infinity;
    for (var i = 0; i < text.charRects.length; i++) {
      final d = text.charRects[i].distanceSquaredTo(pdfPoint);
      if (d < minDist) {
        minDist = d;
        closest = i;
      }
    }
    return closest;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.settings.palette;
    final texture = widget.settings.texture;
    final marginVal = widget.settings.margins.clamp(0.0, 48.0);
    final pdfPage = widget.pageIndex < widget.engine.pageCount
        ? widget.engine.pageAt(widget.pageIndex)
        : null;

    final insetsPadding = EdgeInsets.fromLTRB(
      widget.safeInsets.left + marginVal,
      widget.safeInsets.top + marginVal * 0.35,
      widget.safeInsets.right + marginVal,
      widget.safeInsets.bottom + marginVal * 0.35,
    );

    Widget imageContent;
    if (_loadedImage != null) {
      imageContent = _buildThemedImage(_loadedImage!);
    } else {
      imageContent = FutureBuilder<ui.Image>(
        future: _pendingImage,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This page could not be rendered.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
              ),
            );
          }
          final image = snapshot.data;
          if (image == null) {
            return Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              ),
            );
          }
          return _buildThemedImage(image);
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = math.max(0.0, constraints.maxWidth - insetsPadding.horizontal);
        final availH = math.max(0.0, constraints.maxHeight - insetsPadding.vertical);

        Rect pageRect = Rect.zero;
        if (pdfPage != null && availW > 0 && availH > 0) {
          final pageRatio = pdfPage.width <= 0 ? 1.4 : pdfPage.height / pdfPage.width;
          final availRatio = availH / availW;
          double destW;
          double destH;
          if (availRatio > pageRatio) {
            destW = availW;
            destH = availW * pageRatio;
          } else {
            destH = availH;
            destW = availH / pageRatio;
          }
          final dx = (availW - destW) / 2;
          final dy = (availH - destH) / 2;
          pageRect = Rect.fromLTWH(dx, dy, destW, destH);
        }

        final sel = _selection;
        Rect? handleARect;
        Rect? handleBRect;
        if (sel != null &&
            pdfPage != null &&
            _pageText != null &&
            _pageText!.charRects.isNotEmpty &&
            pageRect != Rect.zero) {
          final aIdx = sel.start.clamp(0, _pageText!.charRects.length - 1);
          final bIdx = (sel.end - 1).clamp(0, _pageText!.charRects.length - 1);
          final rectA = _pageText!.charRects[aIdx]
              .toRect(page: pdfPage, scaledPageSize: pageRect.size)
              .translate(pageRect.left + insetsPadding.left, pageRect.top + insetsPadding.top);
          final rectB = _pageText!.charRects[bIdx]
              .toRect(page: pdfPage, scaledPageSize: pageRect.size)
              .translate(pageRect.left + insetsPadding.left, pageRect.top + insetsPadding.top);
          handleARect = rectA;
          handleBRect = rectB;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // The PDF rendered page image with pinch-zoom support
            InteractiveViewer(
              transformationController: _zoom,
              minScale: 1.0,
              maxScale: 4.5,
              clipBehavior: Clip.none,
              onInteractionEnd: (_) => _reportZoom(),
              child: Padding(
                padding: insetsPadding,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _clearSelection,
                  onLongPressStart: (d) => _onLongPressStart(d, pageRect),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageContent,
                      if (pdfPage != null && pageRect != Rect.zero)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _PdfPageOverlayPainter(
                                page: pdfPage,
                                pageRect: pageRect,
                                scaledPageSize: pageRect.size,
                                pageText: _pageText,
                                highlights: widget.highlights,
                                selection: _selection,
                                selectionColor: Theme.of(context)
                                        .textSelectionTheme
                                        .selectionColor ??
                                    Colors.blue.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Highlights tabs on the right margin
            if (widget.highlights.isNotEmpty)
              Positioned(
                top: widget.safeInsets.top + 16,
                bottom: widget.safeInsets.bottom + 16,
                right: widget.safeInsets.right + 2,
                child: IgnorePointer(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final highlight in widget.highlights)
                        Container(
                          width: 4,
                          height: 16,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: highlight.colorValue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Selection Handles
            if (handleARect != null && handleBRect != null && pdfPage != null) ...[
              Positioned(
                left: handleARect.left - 12,
                top: handleARect.bottom,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final newIdx = _findClosestCharIndex(
                      d.localPosition + handleARect!.bottomLeft - Offset(insetsPadding.left, insetsPadding.top),
                      pageRect,
                    );
                    if (newIdx < sel!.end) {
                      setState(() {
                        _selection = PdfPageTextRange(
                          pageText: _pageText!,
                          start: newIdx,
                          end: sel.end,
                        );
                      });
                    }
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: handleBRect.right - 12,
                top: handleBRect.bottom,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final newIdx = _findClosestCharIndex(
                      d.localPosition + handleBRect!.bottomRight - Offset(insetsPadding.left, insetsPadding.top),
                      pageRect,
                    );
                    if (newIdx > sel!.start) {
                      setState(() {
                        _selection = PdfPageTextRange(
                          pageText: _pageText!,
                          start: sel.start,
                          end: math.min(newIdx + 1, _pageText!.fullText.length),
                        );
                      });
                    }
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],

            // Context Menu Toolbar
            if (_selection != null && _toolbarGlobalPosition != null)
              AdaptiveTextSelectionToolbar.buttonItems(
                anchors: TextSelectionToolbarAnchors(
                  primaryAnchor: _toolbarGlobalPosition!,
                ),
                buttonItems: [
                  if (widget.onTextHighlighted != null)
                    ContextMenuButtonItem(
                      label: 'Highlight',
                      onPressed: () {
                        final s = _selection;
                        if (s != null) {
                          widget.onTextHighlighted?.call(
                            SelectedText(
                              text: s.text,
                              chapter: widget.pageIndex,
                              offset: s.start,
                            ),
                          );
                        }
                        _clearSelection();
                      },
                    ),
                  ContextMenuButtonItem(
                    label: 'Copy',
                    onPressed: () {
                      final s = _selection;
                      if (s != null) {
                        Clipboard.setData(ClipboardData(text: s.text));
                      }
                      _clearSelection();
                    },
                  ),
                  ContextMenuButtonItem(
                    label: 'Select all',
                    onPressed: () {
                      final text = _pageText;
                      if (text != null && text.fullText.isNotEmpty) {
                        setState(() {
                          _selection = PdfPageTextRange(
                            pageText: text,
                            start: 0,
                            end: text.fullText.length,
                          );
                        });
                      }
                    },
                  ),
                ],
              ),

            // Realistic paper texture overlay on top of PDF page
            if (texture != PageTexture.none)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PageTexturePainter(
                      texture: texture,
                      palette: palette,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PdfPageOverlayPainter extends CustomPainter {
  const _PdfPageOverlayPainter({
    required this.page,
    required this.pageRect,
    required this.scaledPageSize,
    required this.pageText,
    required this.highlights,
    required this.selection,
    required this.selectionColor,
  });

  final PdfPage page;
  final Rect pageRect;
  final Size scaledPageSize;
  final PdfPageText? pageText;
  final List<BookHighlight> highlights;
  final PdfPageTextRange? selection;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    final text = pageText;
    if (text == null || text.fullText.isEmpty) return;

    // 1. Paint saved highlights
    for (final h in highlights) {
      int start = h.chapterOffset;
      int end = start + h.length;
      if (h.length <= 0 ||
          start < 0 ||
          end > text.fullText.length ||
          text.fullText.substring(start, end) != h.text) {
        final idx = text.fullText.indexOf(h.text);
        if (idx >= 0) {
          start = idx;
          end = idx + h.text.length;
        } else {
          continue;
        }
      }

      final range = PdfPageTextRange(
        pageText: text,
        start: start.clamp(0, text.fullText.length),
        end: end.clamp(0, text.fullText.length),
      );
      final paint = Paint()
        ..color = h.colorValue.withValues(alpha: 0.38)
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.multiply;

      for (final r in range.enumerateFragmentBoundingRects()) {
        final rect = r.bounds
            .toRect(page: page, scaledPageSize: scaledPageSize)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)),
          paint,
        );
      }
    }

    // 2. Paint active selection
    if (selection != null) {
      final selPaint = Paint()
        ..color = selectionColor
        ..style = PaintingStyle.fill;

      for (final r in selection!.enumerateFragmentBoundingRects()) {
        final rect = r.bounds
            .toRect(page: page, scaledPageSize: scaledPageSize)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)),
          selPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PdfPageOverlayPainter old) {
    return old.page != page ||
        old.pageRect != pageRect ||
        old.scaledPageSize != scaledPageSize ||
        old.pageText != pageText ||
        old.highlights != highlights ||
        old.selection != selection ||
        old.selectionColor != selectionColor;
  }
}
