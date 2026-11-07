import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../core/formatting.dart';
import 'epub_archive.dart';
import 'epub_models.dart';
import 'html_blocks.dart';
import 'image_size.dart';
import 'paths.dart';

class EpubException implements Exception {
  const EpubException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
    required this.path,
  });

  final String id;
  final String href;
  final String mediaType;
  final String properties;
  final String path;
}

class _TocLink {
  const _TocLink(this.title, this.path, this.level);
  final String title;
  final String path;
  final int level;
}

/// Reads EPUB 2/3 books directly from disk, with no server and no network.
class EpubParser {
  static Future<ParsedEpub> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final Archive decoded;
    try {
      decoded = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const EpubException('This file is not a valid EPUB archive.');
    }
    final archive = EpubArchive(decoded);
    if (archive.isEmpty) {
      throw const EpubException('The EPUB archive is empty.');
    }

    final containerBytes = archive.read('META-INF/container.xml');
    if (containerBytes == null) {
      throw const EpubException('Missing META-INF/container.xml.');
    }

    final container = XmlDocument.parse(_decodeText(containerBytes));
    final rootfile = _firstWhere(
      container.descendants.whereType<XmlElement>(),
      (element) => element.name.local == 'rootfile',
    );
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null || opfPath.isEmpty) {
      throw const EpubException('The EPUB has no package document.');
    }

    final opfBytes = archive.read(normalizeArchivePath(opfPath));
    if (opfBytes == null) {
      throw const EpubException('The EPUB package document is missing.');
    }
    final opf = XmlDocument.parse(_decodeText(opfBytes));
    final opfRoot = opf.rootElement;
    final opfDir = archiveDirname(normalizeArchivePath(opfPath));

    final metadata = _firstWhere(
      opfRoot.descendants.whereType<XmlElement>(),
      (element) => element.name.local == 'metadata',
    );

    final title = metadata == null ? null : _metaText(metadata, 'title');
    final author = metadata == null ? null : _metaCreators(metadata);
    final language = metadata == null ? null : _metaText(metadata, 'language');
    final rawDescription =
        metadata == null ? null : _metaText(metadata, 'description');
    final description =
        rawDescription == null ? null : stripHtml(rawDescription);

    // --- manifest -----------------------------------------------------------
    final items = <String, _ManifestItem>{};
    for (final element in opfRoot.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'item') continue;
      final id = element.getAttribute('id');
      final href = element.getAttribute('href');
      if (id == null || href == null || href.isEmpty) continue;
      final path = resolveArchivePath(opfDir, href);
      items[id] = _ManifestItem(
        id: id,
        href: href,
        mediaType: element.getAttribute('media-type') ?? '',
        properties: element.getAttribute('properties') ?? '',
        path: path,
      );
    }

    // --- spine --------------------------------------------------------------
    final spine = _firstWhere(
      opfRoot.descendants.whereType<XmlElement>(),
      (element) => element.name.local == 'spine',
    );

    final order = <_ManifestItem>[];
    final seenPaths = <String>{};
    if (spine != null) {
      for (final ref in spine.descendants.whereType<XmlElement>()) {
        if (ref.name.local != 'itemref') continue;
        if ((ref.getAttribute('linear') ?? '').toLowerCase() == 'no') continue;
        final idref = ref.getAttribute('idref');
        final item = idref == null ? null : items[idref];
        if (item == null) continue;
        if (!_looksLikeHtml(item)) continue;
        if (seenPaths.add(item.path)) order.add(item);
      }
    }

    if (order.isEmpty) {
      final htmlItems = items.values.where(_looksLikeHtml).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final item in htmlItems) {
        if (seenPaths.add(item.path)) order.add(item);
      }
    }

    if (order.isEmpty) {
      throw const EpubException('The EPUB contains no readable chapters.');
    }

    // --- table of contents (nav or ncx) ------------------------------------
    final links = <_TocLink>[];

    final navItem = _firstWhere(
      items.values.where(
          (item) => item.properties.split(RegExp(r'\s+')).contains('nav')),
      (_) => true,
    );
    if (navItem != null) {
      final navBytes = archive.read(navItem.path);
      if (navBytes != null) {
        final document = html_parser.parse(_decodeText(navBytes));
        dom.Element? nav;
        for (final candidate in document.querySelectorAll('nav')) {
          final type = (candidate.attributes['epub:type'] ??
                  candidate.attributes['type'] ??
                  candidate.attributes['role'] ??
                  '')
              .toLowerCase();
          if (type.contains('toc')) {
            nav = candidate;
            break;
          }
        }
        nav ??= document.querySelector('nav');
        if (nav != null) {
          final base = archiveDirname(navItem.path);
          for (final anchor in nav.querySelectorAll('a')) {
            final href = anchor.attributes['href'];
            final label = anchor.text.trim();
            if (href == null || href.isEmpty || label.isEmpty) continue;
            links.add(_TocLink(label, resolveArchivePath(base, href), 0));
          }
        }
      }
    }

    if (links.isEmpty && spine != null) {
      final ncxId = spine.getAttribute('toc');
      _ManifestItem? ncxItem = ncxId == null ? null : items[ncxId];
      ncxItem ??= _firstWhere(
        items.values.where(
          (item) =>
              item.mediaType.contains('dtbncx') ||
              item.path.toLowerCase().endsWith('.ncx'),
        ),
        (_) => true,
      );
      if (ncxItem != null) {
        final ncxBytes = archive.read(ncxItem.path);
        if (ncxBytes != null) {
          links.addAll(_readNcx(ncxBytes, archiveDirname(ncxItem.path)));
        }
      }
    }

    // --- cover --------------------------------------------------------------
    Uint8List? coverBytes;
    _ManifestItem? coverItem = _firstWhere(
      items.values.where(
        (item) => item.properties.split(RegExp(r'\s+')).contains('cover-image'),
      ),
      (_) => true,
    );

    if (coverItem == null && metadata != null) {
      String? coverId;
      for (final element in metadata.descendants.whereType<XmlElement>()) {
        if (element.name.local != 'meta') continue;
        if ((element.getAttribute('name') ?? '').toLowerCase() == 'cover') {
          coverId = element.getAttribute('content');
          break;
        }
      }
      if (coverId != null) coverItem = items[coverId];
    }

    coverItem ??= _firstWhere(
      items.values.where(
        (item) =>
            item.mediaType.startsWith('image/') &&
            RegExp(r'cover', caseSensitive: false).hasMatch(item.href),
      ),
      (_) => true,
    );

    if (coverItem != null) {
      coverBytes = archive.read(coverItem.path);
    }

    if (coverBytes == null) {
      // Some books only expose the cover through the guide page.
      final reference = _firstWhere(
        opfRoot.descendants.whereType<XmlElement>(),
        (element) =>
            element.name.local == 'reference' &&
            (element.getAttribute('type') ?? '').toLowerCase() == 'cover',
      );
      final href = reference?.getAttribute('href');
      if (href != null) {
        final pagePath = resolveArchivePath(opfDir, href);
        final pageBytes = archive.read(pagePath);
        if (pageBytes != null) {
          final page = html_parser.parse(_decodeText(pageBytes));
          final src = page.querySelector('img')?.attributes['src'];
          if (src != null) {
            coverBytes =
                archive.read(resolveArchivePath(archiveDirname(pagePath), src));
          }
        }
      }
    }

    if (coverBytes != null) {
      final dims = imageDimensions(coverBytes);
      if (dims == null || dims.width < 40 || dims.height < 40) {
        coverBytes = null;
      }
    }

    // --- chapters -----------------------------------------------------------
    final chapters = <EpubChapter>[];
    final pathToIndex = <String, int>{};
    final tocTitles = <String, String>{};
    for (final link in links) {
      tocTitles.putIfAbsent(link.path, () => link.title);
    }

    // Keep all extracted artwork within a sensible memory budget. Without a
    // shared cap, every chapter could consume its own allowance and a large
    // illustrated book could exhaust memory.
    var remainingImageBudget = 72 * 1024 * 1024;

    for (final item in order) {
      final chapterBytes = archive.read(item.path);
      if (chapterBytes == null) continue;

      final htmlText = _decodeText(chapterBytes);
      final document = html_parser.parse(htmlText);
      final body = document.body ?? document.documentElement;
      if (body == null) continue;

      final blocks = EpubHtmlBuilder(
        archive: archive,
        basePath: archiveDirname(item.path),
        imageBudget: remainingImageBudget,
      ).build(body);
      for (final block in blocks) {
        if (block is RawImageBlock) {
          remainingImageBudget = math.max(
            0,
            remainingImageBudget - block.bytes.length,
          );
        }
      }

      final hasText = blocks.any(
          (block) => block is RawTextBlock && block.text.trim().isNotEmpty);
      final hasImage = blocks.any((block) => block is RawImageBlock);
      if (!hasText && !hasImage) continue;

      final plain = blocks
          .whereType<RawTextBlock>()
          .map((block) => block.text)
          .join('\n')
          .trim();

      final title = tocTitles[item.path] ??
          _chapterTitle(document) ??
          (plain.isNotEmpty
              ? truncate(plain, 60)
              : 'Chapter ${chapters.length + 1}');

      final index = chapters.length;
      pathToIndex[item.path] = index;
      chapters.add(
        EpubChapter(
          index: index,
          path: item.path,
          href: item.href,
          title: title.trim(),
          blocks: blocks,
          plainText: plain,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const EpubException('No readable text was found in this EPUB.');
    }

    final toc = <EpubTocEntry>[];
    final seenChapters = <int>{};
    for (final link in links) {
      final index = pathToIndex[link.path];
      if (index == null) continue;
      if (!seenChapters.add(index)) continue;
      toc.add(EpubTocEntry(
          title: link.title, chapterIndex: index, level: link.level));
    }
    if (toc.isEmpty) {
      for (final chapter in chapters) {
        toc.add(
            EpubTocEntry(title: chapter.title, chapterIndex: chapter.index));
      }
    }

    return ParsedEpub(
      title: title,
      author: author,
      description: description,
      language: language,
      coverBytes: coverBytes,
      chapters: chapters,
      toc: toc,
    );
  }

  static bool _looksLikeHtml(_ManifestItem item) {
    final media = item.mediaType.toLowerCase();
    final path = item.path.toLowerCase();
    return media.contains('html') ||
        path.endsWith('.xhtml') ||
        path.endsWith('.html') ||
        path.endsWith('.htm');
  }

  static String? _chapterTitle(dom.Document document) {
    for (final tag in ['h1', 'h2', 'h3']) {
      for (final element in document.querySelectorAll(tag)) {
        final text = element.text.trim();
        if (text.isNotEmpty && text.length < 140) return text;
      }
    }
    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) return title;
    return null;
  }

  static List<_TocLink> _readNcx(Uint8List bytes, String baseDir) {
    final links = <_TocLink>[];
    try {
      final document = XmlDocument.parse(_decodeText(bytes));
      for (final navPoint in document.descendants.whereType<XmlElement>()) {
        if (navPoint.name.local != 'navPoint') continue;

        String? label;
        String? src;
        for (final child in navPoint.descendants.whereType<XmlElement>()) {
          if (child.name.local == 'text' && label == null) {
            final text = child.innerText.trim();
            if (text.isNotEmpty) label = text;
          }
          if (child.name.local == 'content' && src == null) {
            src = child.getAttribute('src');
          }
          if (label != null && src != null) break;
        }
        if (label == null || src == null || src.isEmpty) continue;

        var level = 0;
        XmlNode? parent = navPoint.parent;
        while (parent != null) {
          if (parent is XmlElement && parent.name.local == 'navPoint') level++;
          parent = parent.parent;
        }

        links.add(_TocLink(
            label, resolveArchivePath(baseDir, src), level.clamp(0, 3)));
      }
    } catch (_) {
      // A broken NCX should not stop the book from opening.
    }
    return links;
  }

  static T? _firstWhere<T>(
    Iterable<T> elements,
    bool Function(T element) test,
  ) {
    for (final element in elements) {
      if (test(element)) return element;
    }
    return null;
  }

  static String? _metaText(XmlElement metadata, String localName) {
    for (final element in metadata.descendants.whereType<XmlElement>()) {
      if (element.name.local != localName) continue;
      final text = element.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String? _metaCreators(XmlElement metadata) {
    final names = <String>[];
    for (final element in metadata.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'creator') continue;
      final text = element.innerText.trim();
      if (text.isNotEmpty && !names.contains(text)) names.add(text);
    }
    if (names.isEmpty) return null;
    return names.join(', ');
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    if (bytes.length > 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _decodeUtf16(bytes.sublist(2), littleEndian: true);
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _decodeUtf16(bytes.sublist(2), littleEndian: false);
      }
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }

    var declared = '';
    final head = latin1.decode(
      bytes.length > 1200 ? bytes.sublist(0, 1200) : bytes,
      allowInvalid: true,
    );
    final match = RegExp(
      r'''encoding\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(head);
    if (match != null) declared = match.group(1)!.toLowerCase().trim();

    if (declared.contains('utf-16')) {
      final littleEndian =
          !declared.contains('be') && !declared.contains('big');
      return _decodeUtf16(bytes, littleEndian: littleEndian);
    }
    if (declared == 'iso-8859-1' ||
        declared == 'latin1' ||
        declared == 'windows-1252' ||
        declared == 'cp1252') {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(
        littleEndian
            ? bytes[index] | (bytes[index + 1] << 8)
            : (bytes[index] << 8) | bytes[index + 1],
      );
    }
    return String.fromCharCodes(units);
  }
}
