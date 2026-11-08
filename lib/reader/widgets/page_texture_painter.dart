import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/reader_settings.dart';

/// Renders realistic paper grain, parchment flecks, and cloth textures
/// directly onto canvas with rich visual presence.
class PageTexturePainter extends CustomPainter {
  const PageTexturePainter({
    required this.texture,
    required this.palette,
  });

  final PageTexture texture;
  final ReaderPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == PageTexture.none) return;

    final rect = Offset.zero & size;
    final isDark = palette.isDark;

    switch (texture) {
      case PageTexture.none:
        break;

      case PageTexture.parchment:
        _paintParchment(canvas, size, rect, isDark);
        break;

      case PageTexture.handmade:
        _paintHandmade(canvas, size, rect, isDark);
        break;

      case PageTexture.cloth:
        _paintCloth(canvas, size, rect, isDark);
        break;
    }
  }

  void _paintParchment(Canvas canvas, Size size, Rect rect, bool isDark) {
    // Rich aged warm vignette wash around all 4 edges
    final borderVignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          (isDark ? Colors.black : const Color(0xFF63411B))
              .withValues(alpha: isDark ? 0.16 : 0.14),
          (isDark ? Colors.black : const Color(0xFF4A2B0E))
              .withValues(alpha: isDark ? 0.28 : 0.22),
        ],
        stops: const [0.55, 0.85, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, borderVignette);

    // Warm cloudy paper tone variation
    final cloudPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 1.15,
        colors: [
          (isDark ? Colors.white : const Color(0xFFFFFAEC))
              .withValues(alpha: isDark ? 0.05 : 0.08),
          Colors.transparent,
          (isDark ? Colors.black : const Color(0xFF825D34))
              .withValues(alpha: isDark ? 0.12 : 0.10),
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, cloudPaint);

    // Spine gutter depth shadow (left edge of page)
    final spineShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          (isDark ? Colors.black : const Color(0xFF382310))
              .withValues(alpha: isDark ? 0.22 : 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.07],
      ).createShader(rect);
    canvas.drawRect(rect, spineShadow);

    // Fine organic paper flecks and fiber spots
    final rng = math.Random(1337);
    final fleckPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 180; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 0.6 + rng.nextDouble() * 1.6;
      final isLightFleck = rng.nextBool();

      fleckPaint.color = (isDark
              ? (isLightFleck ? Colors.white : Colors.black)
              : (isLightFleck ? const Color(0xFF4A321B) : const Color(0xFF75512B)))
          .withValues(alpha: isDark ? 0.07 : 0.09);

      canvas.drawCircle(Offset(cx, cy), r, fleckPaint);
    }
  }

  void _paintHandmade(Canvas canvas, Size size, Rect rect, bool isDark) {
    final rng = math.Random(42);

    // Deckle edge parchment shading on left and right
    final edgeShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          (isDark ? Colors.black : const Color(0xFF553818))
              .withValues(alpha: isDark ? 0.16 : 0.14),
          Colors.transparent,
          (isDark ? Colors.black : const Color(0xFF553818))
              .withValues(alpha: isDark ? 0.16 : 0.14),
        ],
        stops: const [0.0, 0.05, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, edgeShadow);

    // Visible tactile pulp fibers running across the page
    final fiberPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 220; i++) {
      final y = rng.nextDouble() * size.height;
      final xStart = rng.nextDouble() * (size.width - 50);
      final length = 15.0 + rng.nextDouble() * 55.0;
      final wave = rng.nextDouble() * 4.0 - 2.0;

      final path = Path()
        ..moveTo(xStart, y)
        ..quadraticBezierTo(
          xStart + length * 0.5,
          y + wave,
          xStart + length,
          y + (rng.nextDouble() * 3.0 - 1.5),
        );

      final isDarkFiber = i % 3 != 0;
      fiberPaint
        ..color = (isDark
                ? (isDarkFiber ? const Color(0xFFC7B7A5) : Colors.black)
                : (isDarkFiber ? const Color(0xFF5C3C1B) : const Color(0xFF9E7C57)))
            .withValues(alpha: isDark ? 0.08 : 0.09)
        ..strokeWidth = 0.8 + rng.nextDouble() * 1.2;

      canvas.drawPath(path, fiberPaint);
    }
  }

  void _paintCloth(Canvas canvas, Size size, Rect rect, bool isDark) {
    // Cross-weave cloth texture (tactile textile grid lines)
    final warpPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black)
          .withValues(alpha: isDark ? 0.06 : 0.065)
      ..strokeWidth = 0.85;

    // Vertical warp threads
    const step = 4.5;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), warpPaint);
    }
    // Horizontal weft threads
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), warpPaint);
    }

    // Spine and page corner depth shading
    final spineShade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          (isDark ? Colors.black : const Color(0xFF352210))
              .withValues(alpha: isDark ? 0.22 : 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.09],
      ).createShader(rect);
    canvas.drawRect(rect, spineShade);
  }

  @override
  bool shouldRepaint(covariant PageTexturePainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.palette.page != palette.page ||
        oldDelegate.palette.isDark != palette.isDark;
  }
}
