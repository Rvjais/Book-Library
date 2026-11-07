import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paints a page that is being peeled away.
///
/// [progress] goes from 0 (page flat) to 1 (page completely turned). The layer
/// is a bitmap of the page being turned; the destination page is already
/// painted underneath by `BookPager`.
///
/// With [fromLeft] the page peels from the left edge instead of the right,
/// which is what a backwards page turn looks like.
class PageCurlPainter extends CustomPainter {
  PageCurlPainter({
    required this.image,
    required this.progress,
    this.fromLeft = false,
  });

  final ui.Image image;
  final double progress;
  final bool fromLeft;

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

    // Distance of the fold line from the edge the page is peeled from.
    final fold = width * (1 - t);
    final flapWidth = width - fold;
    // Position of the fold measured from the left of the screen.
    final foldX = fromLeft ? width - fold : fold;
    // Position of the flap's free edge in screen coordinates.
    final freeEdge = fromLeft ? foldX + flapWidth : foldX - flapWidth;

    // The part of the sheet still lying flat.
    canvas.save();
    if (fromLeft) {
      canvas.clipRect(Rect.fromLTWH(foldX, 0, width - foldX, height));
    } else {
      canvas.clipRect(Rect.fromLTWH(0, 0, foldX, height));
    }
    _drawWhole(canvas, size, imagePaint);
    canvas.restore();

    // Shadow cast onto the flat page by the lifted sheet.
    final flatWidth = fromLeft ? width - foldX : foldX;
    if (flatWidth > 2) {
      final shadowWidth = math.min(flatWidth, width * 0.12);
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
              Colors.black.withValues(alpha: 0.34),
              Colors.black.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    if (flapWidth <= 0.5) return;

    // Soft shadow under the free edge.
    final hasRoomForEdge = fromLeft ? freeEdge < width - 2 : freeEdge > 2;
    if (hasRoomForEdge) {
      final shadowWidth = math.min(28.0, math.max(10.0, flapWidth * 0.35));
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
                Colors.black.withValues(alpha: 0.22),
                Colors.black.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }

    // The flap itself, mirrored about the fold line.
    canvas.save();
    if (fromLeft) {
      canvas.translate(foldX + flapWidth, 0);
    } else {
      canvas.translate(foldX, 0);
    }
    canvas.scale(-1, 1);

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

    // Shading across the folded paper.
    final flapRect = Rect.fromLTWH(0, 0, flapWidth, height);
    canvas.drawRect(
      flapRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: fromLeft
              ? [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.32),
                ]
              : [
                  Colors.black.withValues(alpha: 0.32),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.10),
                ],
          stops: const [0, 0.62, 1],
        ).createShader(flapRect),
    );
    canvas.restore();

    // Highlight on the crease.
    canvas.drawRect(
      Rect.fromLTWH(math.max(0, foldX - 1.1), 0, 2.2, height),
      Paint()..color = Colors.white.withValues(alpha: 0.26),
    );
    canvas.drawRect(
      Rect.fromLTWH(math.max(0, foldX - 2.6), 0, 1.2, height),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
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
      oldDelegate.fromLeft != fromLeft;
}
