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
    this.texture = PageTexture.none,
    this.onTapCenter,
    this.pageReady,
    this.gesturesEnabled = true,
  });

  final int pageCount;
  final int pageIndex;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final PageTurnStyle turnStyle;
  final ReaderTheme theme;
  final PageTexture texture;
  final VoidCallback? onTapCenter;

  /// Whether the page at [index] has finished drawing. Bitmap pages (PDF) are
  /// only snapshotted when ready, so a turn can never peel a loading spinner.
  final bool Function(int index)? pageReady;

  /// False while the page is zoomed: page-turn swipes must not fight the
  /// zoom/pan gesture, and edge taps must not jump away from the zoomed area.
  final bool gesturesEnabled;

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
  bool _ignoreDragUntilEnd = false;

  double _dragStartX = 0;
  double _dragStartY = 0;
  double _dragAngle = 0.0;
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
        widget.theme != oldWidget.theme ||
        widget.texture != oldWidget.texture) {
      _cancelCaptureTimers();
      if (widget.pageIndex != _index || widget.pageCount != oldWidget.pageCount) {
        _controller.stop();
        _controller.value = 0;
        _target = null;
        _dragging = false;
        _animating = false;
        _dragDirection = 0;
        _dragAngle = 0.0;
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

  bool _isReady(int index) => widget.pageReady?.call(index) ?? true;

  void _scheduleCapture() {
    _cancelCaptureTimers();
    for (final delay in const [
      Duration(milliseconds: 120),
      Duration(milliseconds: 850),
      Duration(milliseconds: 1600),
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
    // Capturing before the page has painted would freeze a spinner into the
    // page-turn animation.
    if (!_isReady(_index)) return;

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

  void _onDragStart(DragStartDetails details, Size size) {
    if (_animating) return;
    _dragStartX = details.localPosition.dx;
    _dragStartY = details.localPosition.dy;
    // Calculate vertical angle offset (-1.0 at top corner, +1.0 at bottom corner)
    final centerY = size.height * 0.5;
    _dragAngle = centerY <= 0 ? 0.0 : ((_dragStartY - centerY) / centerY).clamp(-1.0, 1.0);
    _dragDirection = 0;
    _dragging = false;
    _ignoreDragUntilEnd = false;
  }

  void _onDragUpdate(DragUpdateDetails details, Size size) {
    if (_animating || _ignoreDragUntilEnd) return;
    final dx = details.localPosition.dx - _dragStartX;
    final dy = details.localPosition.dy - _dragStartY;

    // Follow the drag path dynamically
    final centerY = size.height * 0.5;
    if (centerY > 0) {
      _dragAngle = ((details.localPosition.dy - centerY) / centerY).clamp(-1.0, 1.0);
    }

    if (!_dragging) {
      if (dx.abs() < 12) return;
      final requestedDirection = dx < 0 ? 1 : -1;
      final target = _index + requestedDirection;
      if (target < 0 || target >= widget.pageCount) {
        return; // at edge
      }

      // Instant turns and pages that are not painted yet skip the peel and
      // commit immediately instead of showing a fake 440 ms animation.
      if (widget.turnStyle == PageTurnStyle.none || !_isReady(_index)) {
        _ignoreDragUntilEnd = true;
        _commitInstantly(target);
        return;
      }

      _dragging = true;
      _dragDirection = requestedDirection;
      _direction = requestedDirection;
      _target = target;
      _controller.value = 0;
      unawaited(_capture(force: true));
    }

    // Combine horizontal and vertical diagonal drag distance for natural page response
    final distance = math.sqrt(dx * dx + dy * dy * 0.25);
    final fraction = (distance / size.width).clamp(0.0, 1.0);
    final signMatches = (dx < 0 && _dragDirection == 1) ||
        (dx > 0 && _dragDirection == -1);
    _controller.value = signMatches ? fraction : 0.0;
  }

  void _onDragEnd(DragEndDetails details, Size size) {
    _ignoreDragUntilEnd = false;
    if (!_dragging) return;
    _dragging = false;

    final velocity = details.primaryVelocity ?? 0;
    final forwardVelocity =
        _dragDirection == 1 ? -velocity : velocity;
    final commit = _controller.value > 0.28 || forwardVelocity > 350;

    _animateToEnd(commit: commit);
  }

  void _animateToEnd({required bool commit}) {
    // If no snapshot was captured (or snapshot is stale), commit instantly
    // if dragging past threshold rather than leaving the page stuck in blank drag state
    if (_snapshot == null || _snapshotIndex != _index) {
      if (commit && _target != null) {
        _commitInstantly(_target!);
      } else {
        _commitInstantly(_index);
      }
      return;
    }

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

  /// Flips to [target] with no animation or delay.
  void _commitInstantly(int target) {
    _cancelCaptureTimers();
    _controller.stop();
    _controller.value = 0;
    _target = null;
    _dragDirection = 0;
    _animating = false;
    _dragging = false;
    _index = target.clamp(0, math.max(0, widget.pageCount - 1));
    widget.onPageChanged(_index);
    _disposeSnapshot();
    _scheduleCapture();
    setState(() {});
  }

  void _turnBy(int delta) {
    if (_animating || _dragging) return;
    final target = _index + delta;
    if (target < 0 || target >= widget.pageCount) return;

    // Genuinely instant style, or a page that has not painted yet.
    if (widget.turnStyle == PageTurnStyle.none || !_isReady(_index)) {
      _commitInstantly(target);
      return;
    }

    _direction = delta;
    _target = target;
    _dragAngle = 0.0;
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
      unawaited(
        _capture(force: true).then((_) {
          if (!mounted) return;
          if (_snapshot != null && _snapshotIndex == _index) {
            run();
          } else {
            _commitInstantly(target);
          }
        }),
      );
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

        return RepaintBoundary(
          key: _boundaryKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Removing the recognizers (rather than ignoring inside them) is
            // what lets a zoomed page receive pan and pinch gestures.
            onHorizontalDragStart: widget.gesturesEnabled
                ? (d) => _onDragStart(d, size)
                : null,
            onHorizontalDragUpdate: widget.gesturesEnabled
                ? (d) => _onDragUpdate(d, size)
                : null,
            onHorizontalDragEnd: widget.gesturesEnabled
                ? (d) => _onDragEnd(d, size)
                : null,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final activeTarget = _target;
                final isMoving = (_animating || _dragging) &&
                    activeTarget != null &&
                    _snapshot != null &&
                    _snapshotIndex == _index;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.itemBuilder(
                      context,
                      isMoving ? activeTarget.clamp(0, maxIndex) : clampedIndex,
                    ),
                    if (isMoving)
                      _buildAnimatedLeaf(
                        size: size,
                        image: _snapshot!,
                        progress: _controller.value,
                        dragAngle: _dragAngle,
                        backward: _direction < 0,
                        style: widget.turnStyle,
                      ),

                    // Edge tap areas for turning pages when tapped on left/right 20%
                    // of the screen. Middle area is left open so taps and long-press
                    // text selections reach SelectableText directly without being intercepted.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: size.width * 0.20,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (_) => _turnBy(-1),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: size.width * 0.20,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (_) => _turnBy(1),
                      ),
                    ),
                    // Center tap area for toggling the reader controls
                    Positioned(
                      left: size.width * 0.20,
                      right: size.width * 0.20,
                      top: size.height * 0.35,
                      bottom: size.height * 0.35,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (_) => widget.onTapCenter?.call(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }



  Widget _buildAnimatedLeaf({
    required Size size,
    required ui.Image image,
    required double progress,
    required double dragAngle,
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
              dragAngle: dragAngle,
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
