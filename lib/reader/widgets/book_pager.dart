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
    this.theme = ReaderTheme.light,
    this.onTapCenter,
  });

  final int pageCount;
  final int pageIndex;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final PageTurnStyle turnStyle;
  final ReaderTheme theme;
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
      duration: const Duration(milliseconds: 460),
    );
    _scheduleCapture();
  }

  @override
  void didUpdateWidget(covariant BookPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = math.max(0, widget.pageCount - 1);
    if (widget.pageIndex != _index ||
        widget.pageCount != oldWidget.pageCount ||
        widget.theme != oldWidget.theme) {
      _cancelCaptureTimers();
      if (widget.pageIndex != _index || widget.pageCount != oldWidget.pageCount) {
        _controller.stop();
        _controller.value = 0;
        _target = null;
        _dragging = false;
        _animating = false;
        _dragDirection = 0;
        _index = widget.pageIndex.clamp(0, maxIndex);
      }
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

  void _disposeSnapshot() {
    _snapshot?.dispose();
    _snapshot = null;
    _snapshotIndex = null;
  }

  Future<void> _capture({bool force = false}) async {
    if (_capturing || !mounted) return;
    if (!force && _snapshot != null && _snapshotIndex == _index) return;

    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached) return;

    _capturing = true;
    try {
      final pixelRatio =
          MediaQuery.maybeDevicePixelRatioOf(context)?.clamp(1.0, 2.2) ?? 1.5;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      if (!mounted) {
        image.dispose();
        return;
      }
      _snapshot?.dispose();
      _snapshot = image;
      _snapshotIndex = _index;
    } catch (_) {
      // Fallback: turns degrade to simple slide/fade without snapshot.
    } finally {
      _capturing = false;
    }
  }

  // ------------------------------------------------------------- gestures

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_animating) return;
    _dragStartX = details.localPosition.dx;
    _dragDirection = 0;
    _dragging = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, Size size) {
    if (_animating) return;
    final dx = details.localPosition.dx - _dragStartX;

    if (!_dragging) {
      if (dx.abs() < 12) return;
      final requestedDirection = dx < 0 ? 1 : -1;
      final target = _index + requestedDirection;
      if (target < 0 || target >= widget.pageCount) {
        return; // at edge
      }
      _dragging = true;
      _dragDirection = requestedDirection;
      _direction = requestedDirection;
      _target = target;
      _controller.value = 0;
      unawaited(_capture(force: true));
    }

    final fraction = (dx.abs() / size.width).clamp(0.0, 1.0);
    final signMatches = (dx < 0 && _dragDirection == 1) ||
        (dx > 0 && _dragDirection == -1);
    _controller.value = signMatches ? fraction : 0.0;
  }

  void _onHorizontalDragEnd(DragEndDetails details, Size size) {
    if (!_dragging) return;
    _dragging = false;

    final velocity = details.primaryVelocity ?? 0;
    final forwardVelocity =
        _dragDirection == 1 ? -velocity : velocity;
    final commit = _controller.value > 0.28 || forwardVelocity > 350;

    _animateToEnd(commit: commit);
  }

  void _animateToEnd({required bool commit}) {
    _animating = true;
    final destination = commit ? 1.0 : 0.0;
    final remaining = (destination - _controller.value).abs();
    final durationMs = (remaining * 360).round().clamp(120, 460);

    final curve = commit ? Curves.easeOutCubic : Curves.easeOutQuad;
    _controller
        .animateTo(
          destination,
          duration: Duration(milliseconds: durationMs),
          curve: curve,
        )
        .then((_) {
          if (!mounted) return;
          if (commit && _target != null) {
            _index = _target!;
            widget.onPageChanged(_index);
          }
          _controller.value = 0;
          _target = null;
          _animating = false;
          _disposeSnapshot();
          _scheduleCapture();
          setState(() {});
        });
  }

  void _turnBy(int delta) {
    if (_animating || _dragging) return;
    final target = _index + delta;
    if (target < 0 || target >= widget.pageCount) return;

    _direction = delta;
    _target = target;
    _animating = true;

    void run() {
      if (!mounted) return;
      _controller.value = 0;
      _controller
          .animateTo(
            1.0,
            duration: const Duration(milliseconds: 440),
            curve: Curves.easeInOutCubic,
          )
          .then((_) {
            if (!mounted) return;
            _index = target;
            widget.onPageChanged(_index);
            _controller.value = 0;
            _target = null;
            _animating = false;
            _disposeSnapshot();
            _scheduleCapture();
            setState(() {});
          });
    }

    if (_snapshot != null && _snapshotIndex == _index) {
      run();
    } else {
      unawaited(_capture(force: true).then((_) => run()));
    }
  }

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final maxIndex = math.max(0, widget.pageCount - 1);
    final clampedIndex = _index.clamp(0, maxIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, size),
          onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, size),
          onTapUp: (details) {
            if (_animating || _dragging) return;
            final x = details.localPosition.dx;
            final w = size.width;
            if (x < w * 0.25) {
              _turnBy(-1);
            } else if (x > w * 0.75) {
              _turnBy(1);
            } else {
              widget.onTapCenter?.call();
            }
          },
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final activeTarget = _target;
              final isMoving = (_animating || _dragging) &&
                  activeTarget != null &&
                  _snapshot != null;

              if (!isMoving) {
                return RepaintBoundary(
                  key: _boundaryKey,
                  child: widget.itemBuilder(context, clampedIndex),
                );
              }

              // During animation: incoming page sits underneath, outgoing peels/slides.
              return Stack(
                fit: StackFit.expand,
                children: [
                  widget.itemBuilder(context, activeTarget.clamp(0, maxIndex)),
                  _buildAnimatedLeaf(
                    size: size,
                    image: _snapshot!,
                    progress: _controller.value,
                    backward: _direction < 0,
                    style: widget.turnStyle,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAnimatedLeaf({
    required Size size,
    required ui.Image image,
    required double progress,
    required bool backward,
    required PageTurnStyle style,
  }) {
    final clamped = progress.clamp(0.0, 1.0);

    switch (style) {
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
