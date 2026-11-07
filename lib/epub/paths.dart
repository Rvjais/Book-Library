/// Path helpers for everything inside an EPUB zip.
String normalizeArchivePath(String path) {
  var value = path.replaceAll('\\', '/');
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  final segments = <String>[];
  for (final part in value.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(part);
  }
  return segments.join('/');
}

String archiveDirname(String path) {
  final normalized = normalizeArchivePath(path);
  final index = normalized.lastIndexOf('/');
  return index < 0 ? '' : normalized.substring(0, index);
}

String resolveArchivePath(String baseDir, String href) {
  var target = href.split('#').first;
  target = target.split('?').first;
  try {
    target = Uri.decodeFull(target);
  } catch (_) {
    // Leave malformed escapes alone.
  }
  if (target.startsWith('/')) {
    return normalizeArchivePath(target);
  }
  final base = normalizeArchivePath(baseDir);
  return normalizeArchivePath(base.isEmpty ? target : '$base/$target');
}

String withFragment(String path, [String fragment = '']) =>
    fragment.isEmpty ? path : '$path#$fragment';
