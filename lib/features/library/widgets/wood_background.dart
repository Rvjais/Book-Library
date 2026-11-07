import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Deep walnut boards drawn entirely in code, so the app ships with no images.
class WoodBackgroundPainter extends CustomPainter {
  const WoodBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4B2D19),
            Color(0xFF5E3A22),
            Color(0xFF3E2413),
          ],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );

    final random = math.Random(11);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 80; i++) {
      final y = random.nextDouble() * size.height;
      final amplitude = 1.2 + random.nextDouble() * 7.5;
      final wavelength = 80 + random.nextDouble() * 200;
      final path = Path()..moveTo(-12, y);
      for (var x = 0.0; x <= size.width + 24; x += 16) {
        path.lineTo(
          x,
          y + math.sin((x / wavelength) * math.pi * 2) * amplitude,
        );
      }
      grain
        ..color = (i % 3 == 0 ? Colors.black : Colors.white)
            .withValues(alpha: 0.015 + random.nextDouble() * 0.032)
        ..strokeWidth = 0.5 + random.nextDouble() * 1.5;
      canvas.drawPath(path, grain);
    }

    // Long board seams.
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.20)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 248) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), seam);
    }

    // A few knots.
    for (var i = 0; i < 5; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 5 + random.nextDouble() * 12;
      for (var ring = 0; ring < 3; ring++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: (radius + ring * 5) * 2,
            height: (radius + ring * 3) * 1.1,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Colors.black.withValues(alpha: 0.08 - ring * 0.02),
        );
      }
    }

    // Vignette + readable top area.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.38),
          ],
          stops: const [0.42, 1],
        ).createShader(rect),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.26),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.42),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromLTWH(0, 0, size.width, size.height * 0.26),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant WoodBackgroundPainter oldDelegate) => false;
}

/// The board each row of books stands on.
class ShelfPlankPainter extends CustomPainter {
  const ShelfPlankPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final rect = Offset.zero & size;

    // Shadow of the books on the wall above the board.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, 7),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.34),
          ],
        ).createShader(Rect.fromLTWH(0, 0, width, 7)),
    );

    // Top surface catching the light.
    canvas.drawRect(
      Rect.fromLTWH(0, 6, width, 5),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA97445), Color(0xFF8B5B31)],
        ).createShader(rect),
    );

    // Front face.
    canvas.drawRect(
      Rect.fromLTWH(0, 11, width, 5.5),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6C4626), Color(0xFF412713)],
        ).createShader(rect),
    );

    // Highlight along the lip.
    canvas.drawRect(
      Rect.fromLTWH(0, 10.2, width, 1.1),
      Paint()..color = const Color(0xFFE7D3B0).withValues(alpha: 0.20),
    );

    // Drop shadow below.
    canvas.drawRect(
      Rect.fromLTWH(0, 16.5, width, 2.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.38),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 16.5, width, 2.5)),
    );

    // Small brass nails.
    final nail = Paint()..color = const Color(0xFFC9A66B).withValues(alpha: 0.35);
    for (var x = 18.0; x < width - 10; x += 74) {
      canvas.drawCircle(Offset(x, 13.5), 0.9, nail);
    }
  }

  @override
  bool shouldRepaint(covariant ShelfPlankPainter oldDelegate) => false;
}
