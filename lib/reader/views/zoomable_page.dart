import 'package:flutter/material.dart';

/// Pinch-to-zoom wrapper for pages whose content is drawn by Flutter widgets
/// (EPUB). PDFs have their own zoom inside `PdfPageView`.
///
/// `SelectableText` wins the gesture arena against `InteractiveViewer`, which
/// made pinch-to-zoom impossible on EPUB pages. This widget therefore listens
/// to raw pointers instead of competing in the arena: text selection, page-turn
/// swipes and taps keep working exactly as before, while two fingers drive the
/// transform directly.
class ZoomablePage extends StatefulWidget {
  const ZoomablePage({
    super.key,
    required this.child,
    this.onZoomChanged,
    this.minScale = 1.0,
    this.maxScale = 4.0,
  });

  final Widget child;
  final ValueChanged<bool>? onZoomChanged;
  final double minScale;
  final double maxScale;

  @override
  State<ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<ZoomablePage> {
  final Map<int, Offset> _pointers = <int, Offset>{};

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double? _lastDistance;
  Offset? _lastFocal;
  bool _zoomed = false;

  bool get _isZoomed => _scale > 1.02;

  Matrix4 get _matrix => Matrix4.identity()
    ..translateByDouble(_offset.dx, _offset.dy, 0.0, 1.0)
    ..scaleByDouble(_scale, _scale, _scale, 1.0);

  void _resetBaseline() {
    _lastDistance = null;
    _lastFocal = null;
  }

  void _clampOffset() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final w = box.size.width;
    final h = box.size.height;
    // Keep the scaled page covering the viewport so it can never be dragged
    // into an empty void.
    final minX = w - w * _scale;
    final minY = h - h * _scale;
    _offset = Offset(
      _offset.dx.clamp(minX, 0.0),
      _offset.dy.clamp(minY, 0.0),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _resetBaseline();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      _updatePinch();
      return;
    }

    // One finger pans only while already magnified; otherwise the drag must
    // stay available for text selection and page turns.
    if (_scale <= 1.001) return;
    setState(() {
      _offset += event.localPosition - previous;
      _clampOffset();
    });
  }

  void _updatePinch() {
    final points = _pointers.values.take(2).toList(growable: false);
    final focal = (points[0] + points[1]) / 2;
    final distance = (points[0] - points[1]).distance;

    final lastDistance = _lastDistance;
    final lastFocal = _lastFocal;
    if (lastDistance == null || lastFocal == null || lastDistance < 1) {
      _lastDistance = distance;
      _lastFocal = focal;
      return;
    }

    final ratio = distance / lastDistance;
    final nextScale = (_scale * ratio).clamp(
      widget.minScale,
      widget.maxScale,
    );
    if ((nextScale - _scale).abs() > 0.0001) {
      // Keep the content under the pinch focal point pinned in place.
      final sceneFocal = (focal - _offset) / _scale;
      setState(() {
        _scale = nextScale;
        _offset = focal - sceneFocal * _scale;
        _clampOffset();
      });
    }

    _lastDistance = distance;
    _lastFocal = focal;
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    _resetBaseline();
    if (_pointers.isNotEmpty) return;

    // Snap back to a clean fit when the pinch ends at (almost) 1x.
    if (_scale < 1.02) {
      setState(() {
        _scale = 1.0;
        _offset = Offset.zero;
      });
    }
    _reportZoom();
  }

  void _reportZoom() {
    final zoomed = _isZoomed;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ClipRect(
        child: Transform(
          transform: _matrix,
          alignment: Alignment.topLeft,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              // While magnified, stop the text layer from interpreting pans as
              // selection drags; the raw listener above still gets the events.
              if (_isZoomed) const Positioned.fill(child: AbsorbPointer()),
            ],
          ),
        ),
      ),
    );
  }
}
