import 'dart:math' as math;
import 'dart:typed_data';

/// Reads the pixel dimensions out of PNG, JPEG, GIF and WebP headers without
/// decoding the whole image. Returns null for formats we can't inspect.
({int width, int height})? imageDimensions(Uint8List bytes) {
  if (bytes.length < 10) return null;

  // PNG
  if (bytes.length > 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final width = _be32(bytes, 16);
    final height = _be32(bytes, 20);
    if (width > 0 && height > 0) return (width: width, height: height);
  }

  // GIF
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    final width = bytes[6] | (bytes[7] << 8);
    final height = bytes[8] | (bytes[9] << 8);
    if (width > 0 && height > 0) return (width: width, height: height);
  }

  // WebP (VP8 / VP8L / VP8X)
  if (bytes.length > 30 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    if (chunk == 'VP8X') {
      final width = 1 + _le24(bytes, 24);
      final height = 1 + _le24(bytes, 27);
      return (width: width, height: height);
    }
    if (chunk == 'VP8 ') {
      final width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
      final height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
      if (width > 0 && height > 0) return (width: width, height: height);
    }
    if (chunk == 'VP8L') {
      final bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
      final width = (bits & 0x3FFF) + 1;
      final height = ((bits >> 14) & 0x3FFF) + 1;
      return (width: width, height: height);
    }
  }

  // JPEG: walk markers until a Start Of Frame segment.
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var index = 2;
    while (index + 9 < bytes.length) {
      if (bytes[index] != 0xFF) {
        index++;
        continue;
      }
      final marker = bytes[index + 1];
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        index += 2;
        continue;
      }
      final length = (bytes[index + 2] << 8) | bytes[index + 3];
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final height = (bytes[index + 5] << 8) | bytes[index + 6];
        final width = (bytes[index + 7] << 8) | bytes[index + 8];
        if (width > 0 && height > 0) return (width: width, height: height);
      }
      index += 2 + math.max(2, length);
    }
  }

  return null;
}

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _le24(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
