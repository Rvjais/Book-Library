import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paints a page peeling realistically at any diagonal drag angle.
///
/// [progress] goes from 0 (flat) to 1 (turned).
/// [dragAngle] is the normalized vertical drag direction (-1.0 top corner, +1.0 bottom corner).
class PageCurlPainter extends CustomPainter {
  PageCurlPainter({
    required this.image,
    required this.progress,
    this.fromLeft = false,
    this.dragAngle = 0.0,
  });

  final ui.Image image;
  final double progress;
  final bool fromLeft;
  final double dragAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    if (width <= 0 || height <= 0) return;

    final t = progress.clamp(0.0, 1.0);
    final imagePaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;

    if (t <= 0.002) {
      _drawWhole(canvas, size, imagePaint);
      return;
    }
    if (t >= 0.998) return;

    // Angle curl tilt offset based on where user grabbed the page (top/bottom)
    final tilt = dragAngle.clamp(-0.85, 0.85) * (1 - t) * 45.0;

    // Distance of fold line from peeling edge
    final fold = width * (1 - t);
    final flapWidth = width - fold;
    final foldX = fromLeft ? width - fold : fold;
    final freeEdge = fromLeft ? foldX + flapWidth : foldX - flapWidth;

    // 1. The part of the sheet still lying flat
    canvas.save();
    final flatPath = Path();
    if (fromLeft) {
      flatPath.moveTo(foldX + tilt * 0.5, 0);
      flatPath.lineTo(width, 0);
      flatPath.lineTo(width, height);
      flatPath.lineTo(foldX - tilt * 0.5, height);
      flatPath.close();
    } else {
      flatPath.moveTo(0, 0);
      flatPath.lineTo(foldX - tilt * 0.5, 0);
      flatPath.lineTo(foldX + tilt * 0.5, height);
      flatPath.lineTo(0, height);
      flatPath.close();
    }
    canvas.clipPath(flatPath);
    _drawWhole(canvas, size, imagePaint);
    canvas.restore();

    // 2. Realistic depth shadow on the flat page cast by the lifted curling sheet
    final flatWidth = fromLeft ? width - foldX : foldX;
    if (flatWidth > 2) {
      final shadowWidth = math.min(flatWidth, width * 0.16);
      final rect = fromLeft
          ? Rect.fromLTWH(foldX, 0, shadowWidth, height)
          : Rect.fromLTWH(foldX - shadowWidth, 0, shadowWidth, height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              Colors.black.withValues(alpha: 0.38),
              Colors.black.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    if (flapWidth <= 0.5) return;

    // 3. Soft ambient shadow under the free curl edge
    final hasRoomForEdge = fromLeft ? freeEdge < width - 2 : freeEdge > 2;
    if (hasRoomForEdge) {
      final shadowWidth = math.min(32.0, math.max(12.0, flapWidth * 0.4));
      final left = fromLeft ? freeEdge : freeEdge - shadowWidth;
      final rect = Rect.fromLTWH(left, 0, shadowWidth, height);
      if (rect.width > 1) {
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                Colors.black.withValues(alpha: 0.26),
                Colors.black.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }

    // 4. The curled flap, mirrored and angled naturally
    canvas.save();
    if (fromLeft) {
      canvas.translate(foldX + flapWidth, 0);
    } else {
      canvas.translate(foldX, 0);
    }
    canvas.scale(-1, 1);

    // Apply angular paper curl skew
    final skewAngle = (tilt / height) * 0.5;
    canvas.transform(Matrix4.skewY(skewAngle).storage);

    final scale = image.width / width;
    final srcLeft = fromLeft ? 0.0 : fold * scale;
    final srcWidth = math.max(
      0.0,
      math.min(
        image.width - srcLeft,
        flapWidth * scale,
      ),
    );
    if (srcWidth > 0.5) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(srcLeft, 0, srcWidth, image.height.toDouble()),
        Rect.fromLTWH(0, 0, flapWidth, height),
        imagePaint,
      );
    }

    // Shading across the curved cylindrical page roll
    final flapRect = Rect.fromLTWH(0, 0, flapWidth, height);
    canvas.drawRect(
      flapRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: fromLeft
              ? [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.09),
                  Colors.black.withValues(alpha: 0.38),
                ]
              : [
                  Colors.black.withValues(alpha: 0.38),
                  Colors.black.withValues(alpha: 0.09),
                  Colors.white.withValues(alpha: 0.16),
                ],
          stops: const [0, 0.58, 1],
        ).createShader(flapRect),
    );
    canvas.restore();

    // Crease and specular highlight along the rolling cylinder ridge
    canvas.drawRect(
      Rect.fromLTWH(math.max(0, foldX - 1.2), 0, 2.4, height),
      Paint()..color = Colors.white.withValues(alpha: 0.32),
    );
    canvas.drawRect(
      Rect.fromLTWH(math.max(0, foldX - 2.8), 0, 1.4, height),
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );
  }

  void _drawWhole(Canvas canvas, Size size, Paint paint) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant PageCurlPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.progress != progress ||
      oldDelegate.fromLeft != fromLeft ||
      oldDelegate.dragAngle != dragAngle;
}
