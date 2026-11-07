import 'dart:io';

import 'package:image/image.dart' as img;

/// Draws the LibReady launcher icon (a small wooden shelf of books) and writes
/// every Android/iOS launcher size used by the project.
///
/// Run from the project root with:
///   dart run tool/generate_icons.dart
void main() {
  final icon = _drawIcon(1024);

  const android = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
  };

  const ios = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };

  android.forEach((path, size) {
    _write(icon, path, size);
  });
  ios.forEach((name, size) {
    _write(icon, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/$name', size);
  });

  stdout.writeln('Wrote ${android.length + ios.length} launcher icons.');
}

void _write(img.Image source, String path, int size) {
  final resized = size == source.width
      ? source
      : img.copyResize(
          source,
          width: size,
          height: size,
          interpolation: img.Interpolation.cubic,
        );
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(resized, level: 9));
}

img.Image _drawIcon(int size) {
  final image = img.Image(width: size, height: size);

  // Warm wood background.
  img.fill(image, color: _rgb(62, 36, 19));
  for (var x = 0; x < size; x += 14) {
    final strength = 8 + ((x * 7) % 11);
    img.drawLine(
      image,
      x1: x,
      y1: 0,
      x2: x + 12,
      y2: size,
      color: _rgba(122, 76, 40, strength),
      thickness: 6,
    );
  }
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: size,
    y2: size,
    color: _rgba(24, 12, 5, 70),
    alphaBlend: true,
  );

  // Shelf plank.
  img.fillRect(
    image,
    x1: 118,
    y1: 744,
    x2: 906,
    y2: 846,
    color: _rgb(116, 70, 38),
    radius: 16,
  );
  img.fillRect(
    image,
    x1: 118,
    y1: 744,
    x2: 906,
    y2: 766,
    color: _rgba(190, 136, 78, 150),
    radius: 12,
  );
  img.fillRect(
    image,
    x1: 144,
    y1: 838,
    x2: 880,
    y2: 862,
    color: _rgba(28, 14, 6, 120),
    radius: 10,
  );

  // Books, back to front.
  _book(
    image,
    left: 214,
    top: 412,
    right: 388,
    bottom: 750,
    cover: _rgb(104, 55, 47),
    spine: _rgb(139, 78, 63),
    accent: _rgb(206, 166, 107),
  );
  _book(
    image,
    left: 636,
    top: 452,
    right: 808,
    bottom: 750,
    cover: _rgb(47, 90, 92),
    spine: _rgb(70, 122, 122),
    accent: _rgb(205, 185, 143),
  );
  _book(
    image,
    left: 400,
    top: 326,
    right: 620,
    bottom: 750,
    cover: _rgb(74, 45, 24),
    spine: _rgb(163, 115, 58),
    accent: _rgb(243, 232, 210),
    wide: true,
  );

  // A brass bookmark ribbon on the centre book.
  img.fillRect(
    image,
    x1: 478,
    y1: 326,
    x2: 520,
    y2: 472,
    color: _rgb(195, 154, 95),
    radius: 4,
  );
  img.fillPolygon(
    image,
    vertices: [
      img.Point(478, 472),
      img.Point(520, 472),
      img.Point(499, 512),
    ],
    color: _rgb(195, 154, 95),
  );

  // Title rules on the centre cover.
  for (var i = 0; i < 4; i++) {
    final y = 560 + i * 32;
    final width = i == 3 ? 96 : 156 - i * 12;
    img.fillRect(
      image,
      x1: 436,
      y1: y,
      x2: 436 + width,
      y2: y + 12,
      color: _rgba(240, 226, 198, i == 3 ? 150 : 205),
      radius: 6,
    );
  }

  // Soft vignette so the shelf sits in the frame.
  for (var i = 0; i < 90; i++) {
    img.drawRect(
      image,
      x1: i,
      y1: i,
      x2: size - 1 - i,
      y2: size - 1 - i,
      color: _rgba(20, 10, 4, 3),
    );
  }

  return image;
}

void _book(
  img.Image image, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required img.Color cover,
  required img.Color spine,
  required img.Color accent,
  bool wide = false,
}) {
  // Drop shadow.
  img.fillRect(
    image,
    x1: left + 14,
    y1: top + 18,
    x2: right + 22,
    y2: bottom + 18,
    color: _rgba(0, 0, 0, 90),
    radius: 16,
  );
  // Cover.
  img.fillRect(
    image,
    x1: left,
    y1: top,
    x2: right,
    y2: bottom,
    color: cover,
    radius: 12,
  );
  // Spine on the left edge.
  img.fillRect(
    image,
    x1: left,
    y1: top,
    x2: left + 26,
    y2: bottom,
    color: spine,
    radius: 12,
  );
  img.fillRect(
    image,
    x1: left + 4,
    y1: top + 22,
    x2: left + 9,
    y2: bottom - 22,
    color: _rgba(255, 246, 228, 70),
    radius: 3,
  );
  // Cover border.
  img.drawRect(
    image,
    x1: left + (wide ? 44 : 40),
    y1: top + 30,
    x2: right - 24,
    y2: bottom - 30,
    color: accent,
    thickness: 4,
  );
  // Page block on the right edge.
  img.fillRect(
    image,
    x1: right - 8,
    y1: top + 18,
    x2: right + 6,
    y2: bottom - 18,
    color: _rgb(238, 226, 202),
    radius: 4,
  );
  // Top and bottom sheen.
  img.fillRect(
    image,
    x1: left + 8,
    y1: top,
    x2: right - 8,
    y2: top + 10,
    color: _rgba(255, 244, 222, 60),
    radius: 6,
  );
  img.fillRect(
    image,
    x1: left + 8,
    y1: bottom - 20,
    x2: right - 8,
    y2: bottom - 8,
    color: _rgba(0, 0, 0, 55),
    radius: 6,
  );
}

img.Color _rgb(int r, int g, int b) => img.ColorRgb8(r, g, b);

img.Color _rgba(int r, int g, int b, int a) => img.ColorRgba8(r, g, b, a);
