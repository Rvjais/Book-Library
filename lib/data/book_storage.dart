import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns everything LibReady writes to disk.
///
/// Files live inside the app's documents directory:
///   LibReady/books/&lt;id&gt;.pdf
///   LibReady/covers/&lt;id&gt;_&lt;stamp&gt;.jpg
class BookStorage {
  Directory? _root;

  Future<Directory> root() async {
    final cached = _root;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'LibReady'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  Future<Directory> _sub(String name) async {
    final dir = Directory(p.join((await root()).path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> booksDir() => _sub('books');

  Future<Directory> coversDir() => _sub('covers');

  /// Copies a picked file into private storage and returns its new path.
  Future<String> importPickedFile(PlatformFile file, String id, String ext) async {
    final destination = File(p.join((await booksDir()).path, '$id.$ext'));
    final sourcePath = file.path;
    if (sourcePath != null && sourcePath.isNotEmpty) {
      await File(sourcePath).copy(destination.path);
    } else {
      final sink = destination.openWrite();
      await sink.addStream(file.readAsByteStream());
      await sink.close();
    }
    return destination.path;
  }

  Future<String> writeCover(String id, Uint8List jpegBytes) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join((await coversDir()).path, '${id}_$stamp.jpg'));
    await file.writeAsBytes(jpegBytes, flush: true);
    return file.path;
  }

  Future<String> writeBytes(String id, String ext, Uint8List bytes) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join((await booksDir()).path, '${id}_$stamp.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing we can do; the library entry is removed either way.
    }
  }

  Future<int> usedBytes() async {
    var total = 0;
    for (final dir in [await booksDir(), await coversDir()]) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // Skip unreadable files.
          }
        }
      }
    }
    return total;
  }

  Future<void> deleteEverything() async {
    final rootDir = await root();
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
    _root = null;
  }
}
