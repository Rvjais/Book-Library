import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../data/book_storage.dart';

/// Turns raw cover art (PNG/JPEG/WebP/GIF from an EPUB or a rendered PDF page)
/// into a reasonably sized JPEG stored in the app folder.
class CoverService {
  const CoverService();

  Future<String?> save(
    BookStorage storage,
    String bookId,
    Uint8List? raw, {
    int maxWidth = 900,
  }) async {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;

      var cover = decoded;
      if (cover.width > maxWidth) {
        cover = img.copyResize(cover, width: maxWidth);
      }
      final maxHeight = (maxWidth * 1.7).round();
      if (cover.height > maxHeight) {
        cover = img.copyResize(cover, height: maxHeight);
      }

      final jpeg = img.encodeJpg(cover, quality: 88);
      return await storage.writeCover(bookId, jpeg);
    } catch (_) {
      return null;
    }
  }
}
