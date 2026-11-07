import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/reader_settings.dart';
import 'page_curl_painter.dart';

/// A page host with real page-turn gestures and several turn styles.
///
/// The outgoing page is captured as a bitmap, which lets the animation peel,
/// flip or slide it while the incoming page is already rendered underneath.
class BookPager extends StatefulWidget {
  const BookPager({
    super.key,
    required this.pageCount,
    required this.pageIndex,
    required this.itemBuilder,
    required this.onPageChanged,
    this.turnStyle = PageTurnStyle.curl,
    this.onTapCenter,
  });

  final int pageCount;
  final int pageIndex;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final PageTurnStyle turnStyle;
  final VoidCallback? onTapCenter;

  @override
  State<BookPager> createState() => _BookPagerState();
}

class _BookPagerState extends State<BookPager>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _controller;

  late int _index;
  int? _target;
  int _direction = 1;

  bool _dragging = false;
  bool _animating = false;
  bool _capturing = false;

  double _dragStartX = 0;
  int _dragDirection = 0;

  ui.Image? _snapshot;
  int? _snapshotIndex;

  final List<Timer> _captureTimers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _index = widget.pageIndex.clamp(0, math.max(0, widget.pageCount - 1));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _scheduleCapture();
  }

  @override
  void didUpdateWidget(covariant BookPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = math.max(0, widget.pageCount - 1);
    if (widget.pageIndex != _index || widget.pageCount != oldWidget.pageCount) {
      _cancelCaptureTimers();
      _controller.stop();
      _controller.value = 0;
      _target = null;
      _dragging = false;
      _animating = false;
      _dragDirection = 0;
      _index = widget.pageIndex.clamp(0, maxIndex);
      _disposeSnapshot();
      _scheduleCapture();
    }
  }

  @override
  void dispose() {
    _cancelCaptureTimers();
    _controller.dispose();
    _disposeSnapshot();
    super.dispose();
  }

  // ------------------------------------------------------------- snapshots

  void _scheduleCapture() {
    _cancelCaptureTimers();
    for (final delay in const [
      Duration(milliseconds: 120),
      Duration(milliseconds: 850),
    ]) {
      _captureTimers.add(
        Timer(delay, () {
          if (!mounted || _animating || _dragging) return;
          unawaited(_capture(force: true));
        }),
      );
    }
  }

  void _cancelCaptureTimers() {
    for (final timer in _captureTimers) {
      timer.cancel();
    }
    _captureTimers.clear();
  }

  Future<ui.Image?> _grabPage() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final boundary = _boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      final ratio = math.min(MediaQuery.devicePixelRatioOf(context), 1.6);
      return await boundary.toImage(pixelRatio: math.max(1.0, ratio));
    } catch (_) {
      return null;
    }
  }

  Future<void> _capture({bool force = false}) async {
    if (_capturing || !mounted || _animating || _dragging) return;
    if (!force && _snapshot != null && _snapshotIndex == _index) return;
    _capturing = true;
    try {
      final image = await _grabPage();
      if (image == null) return;
      if (!mounted || _animating || _dragging) {
        image.dispose();
        return;
      }
      final previous = _snapshot;
      _snapshot = image;
      _snapshotIndex = _index;
      previous?.dispose();
    } finally {
      _capturing = false;
    }
  }

  void _disposeSnapshot() {
    _snapshot?.dispose();
    _snapshot = null;
    _snapshotIndex = null;
  }

  // ---------------------------------------------------------------- turning

  Future<void> turn(int direction) async {
    if (_animating || _dragging || direction == 0) return;
    final target = _index + direction;
    if (target < 0 || target >= widget.pageCount) return;

    if (widget.turnStyle == PageTurnStyle.none) {
      _commitInstant(target);
      return;
    }

    _cancelCaptureTimers();

    var image = (_snapshotIndex == _index) ? _snapshot : null;
    if (image == null) {
      image = await _grabPage();
      if (!mounted) {
        image?.dispose();
        return;
      }
    }
    if (image == null) {
      _commitInstant(target);
      return;
    }

    final previous = _snapshot;
    _snapshot = image;
    _snapshotIndex = _index;
    if (previous != null && !identical(previous, image)) previous.dispose();

    setState(() {
      _target = target;
      _direction = direction;
      _animating = true;
      _controller.value = 0;
    });

    try {
      await _controller.animateTo(
        1,
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {
      // A disposed controller while navigating back is harmless.
    }
    if (!mounted) return;
    _commit(target);
  }

  void _commitInstant(int target) {
    _cancelCaptureTimers();
    _controller.value = 0;
    setState(() {
      _index = target;
      _target = null;
      _direction = 1;
      _animating = false;
      _dragging = false;
    });
    widget.onPageChanged(target);
    _disposeSnapshot();
    _scheduleCapture();
  }

  void _commit(int target) {
    _controller.value = 0;
    setState(() {
      _index = target;
      _target = null;
      _direction = 1;
      _animating = false;
    });
    widget.onPageChanged(target);
    _disposeSnapshot();
    _scheduleCapture();
  }

  // ------------------------------------------------------------------ input

  void _handleTap(TapUpDetails details) {
    if (_animating || _dragging) return;
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    final x = details.localPosition.dx;
    if (x < width * 0.22) {
      unawaited(turn(-1));
    } else if (x > width * 0.78) {
      unawaited(turn(1));
    } else {
      widget.onTapCenter?.call();
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (_animating || widget.pageCount <= 1) return;
    _dragStartX = details.localPosition.dx;
    _dragDirection = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_animating) return;
    final dx = details.localPosition.dx - _dragStartX;

    if (_dragDirection == 0) {
      if (dx.abs() < 16) return;
      final direction = dx < 0 ? 1 : -1;
      final target = _index + direction;
      if (target < 0 || target >= widget.pageCount) return;

      if (_snapshot == null || _snapshotIndex != _index) {
        // Not captured yet: fall back to a normal animated turn.
        _dragDirection = direction;
        unawaited(turn(direction));
        return;
      }

      _cancelCaptureTimers();
      _dragDirection = direction;
      setState(() {
        _target = target;
        _direction = direction;
        _dragging = true;
        _controller.value = 0;
      });
    }

    if (!_dragging) return;
    final width = context.size?.width ?? 1;
    final value = (dx.abs() / (width * 0.85)).clamp(0.0, 1.0);
    _controller.value = value;
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (!_dragging || _target == null) {
      _dragDirection = 0;
      return;
    }
    final target = _target!;
    final velocity = details.primaryVelocity ?? 0;
    final value = _controller.value;
    final complete = value > 0.32 || velocity.abs() > 520;

    setState(() => _dragging = false);

    if (complete) {
      try {
        await _controller.animateTo(
          1,
          duration: Duration(
            milliseconds: math.max(70, (280 * (1 - value)).round()),
          ),
          curve: Curves.easeOut,
        );
      } catch (_) {}
      _dragDirection = 0;
      if (!mounted) return;
      _commit(target);
    } else {
      try {
        await _controller.animateTo(
          0,
          duration: Duration(
            milliseconds: math.max(70, (240 * value).round()),
          ),
          curve: Curves.easeOut,
        );
      } catch (_) {}
      _dragDirection = 0;
      if (!mounted) return;
      setState(() {
        _target = null;
        _direction = 1;
      });
      _controller.value = 0;
      _scheduleCapture();
    }
  }

  void _cancelDrag() {
    _dragDirection = 0;
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _target = null;
      _direction = 1;
    });
    _controller.value = 0;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final baseIndex =
        (_target ?? _index).clamp(0, math.max(0, widget.pageCount - 1)).toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _handleTap,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _cancelDrag,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                key: _boundaryKey,
                child: widget.itemBuilder(context, baseIndex),
              ),
              if (_target != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return _effect(_controller.value, size);
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _effect(double progress, Size size) {
    final image = _snapshot;
    if (image == null) return const SizedBox.shrink();
    final clamped = progress.clamp(0.0, 1.0);
    final backward = _direction < 0;

    switch (widget.turnStyle) {
      case PageTurnStyle.curl:
        return SizedBox.expand(
          child: CustomPaint(
            painter: PageCurlPainter(
              image: image,
              progress: clamped,
              fromLeft: backward,
            ),
          ),
        );

      case PageTurnStyle.flip:
        final angle = (backward ? 1 : -1) * math.pi * clamped;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateY(angle);
        final shade = math.sin(math.pi * clamped).clamp(0.0, 1.0);
        return Transform(
          alignment: backward ? Alignment.centerRight : Alignment.centerLeft,
          transform: transform,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RawImage(image: image, fit: BoxFit.fill),
              if (shade > 0.02)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.42 * shade),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.10 * shade),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
            ],
          ),
        );

      case PageTurnStyle.slide:
        return Transform.translate(
          offset: Offset((backward ? 1 : -1) * size.width * clamped, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: Offset(backward ? -8 : 8, 0),
                ),
              ],
            ),
            child: RawImage(image: image, fit: BoxFit.fill),
          ),
        );

      case PageTurnStyle.fade:
        return Opacity(
          opacity: (1 - clamped).clamp(0.0, 1.0),
          child: RawImage(image: image, fit: BoxFit.fill),
        );

      case PageTurnStyle.none:
        return const SizedBox.shrink();
    }
  }
}
