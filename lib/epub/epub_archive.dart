import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Case-insensitive view over the EPUB zip.
class EpubArchive {
  EpubArchive(this.archive) {
    for (final file in archive.files) {
      _files.putIfAbsent(_key(file.name), () => file);
    }
  }

  final Archive archive;
  final Map<String, ArchiveFile> _files = {};

  static String _key(String path) =>
      path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '').toLowerCase();

  ArchiveFile? find(String path) => _files[_key(path)];

  Uint8List? read(String path) => find(path)?.content;

  bool get isEmpty => _files.isEmpty;
}
