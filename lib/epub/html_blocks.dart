import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;

import 'epub_archive.dart';
import 'epub_models.dart';
import 'image_size.dart';
import 'paths.dart';

/// Converts an XHTML chapter into simple blocks the paginator understands.
///
/// This is intentionally not a full CSS engine: LibReady reads the *text* of a
/// book with sensible typography chosen by the reader, which keeps pagination
/// fast and lets the page-curl animation stay smooth.
class EpubHtmlBuilder {
  EpubHtmlBuilder({
    required this.archive,
    required this.basePath,
    this.imageBudget = 48 * 1024 * 1024,
  });

  final EpubArchive archive;
  final String basePath;
  int imageBudget;

  final List<Object> _blocks = [];
  final List<RawRun> _runs = [];

  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  bool _monospace = false;
  bool _link = false;
  bool _preserveWhitespace = false;
  int _offset = 0;

  List<Object> build(dom.Element body) {
    _visitChildren(body);
    _flush(BlockKind.paragraph);
    return _blocks;
  }

  // ---------------------------------------------------------------- visitors

  void _visitChildren(dom.Node node) {
    for (final child in node.nodes) {
      _visit(child);
    }
  }

  void _visit(dom.Node node) {
    if (node is dom.Text) {
      _addText(node.text);
      return;
    }
    if (node is! dom.Element) return;

    final tag = (node.localName ?? '').toLowerCase();
    switch (tag) {
      case '':
        return;
      case 'script':
      case 'style':
      case 'head':
      case 'title':
      case 'meta':
      case 'link':
      case 'svg':
      case 'input':
      case 'button':
      case 'iframe':
      case 'audio':
      case 'video':
        return;

      case 'br':
        _runs.add(_run('\n'));
        return;

      case 'hr':
        _flush(BlockKind.paragraph);
        _blocks.add(const RawRuleBlock());
        return;

      case 'img':
      case 'image':
        _flush(BlockKind.paragraph);
        _addImage(node);
        return;

      case 'p':
      case 'div':
      case 'section':
      case 'article':
      case 'header':
      case 'footer':
      case 'main':
      case 'aside':
      case 'figure':
      case 'figcaption':
      case 'tr':
      case 'td':
      case 'th':
      case 'dd':
      case 'dt':
      case 'center':
      case 'nav':
        _flush(BlockKind.paragraph);
        _visitChildren(node);
        _flush(BlockKind.paragraph);
        return;

      case 'blockquote':
        _flush(BlockKind.paragraph);
        _visitChildren(node);
        _flush(BlockKind.quote);
        return;

      case 'h1':
        _styledBlock(node, BlockKind.heading1);
        return;
      case 'h2':
        _styledBlock(node, BlockKind.heading2);
        return;
      case 'h3':
        _styledBlock(node, BlockKind.heading3);
        return;
      case 'h4':
        _styledBlock(node, BlockKind.heading4);
        return;
      case 'h5':
        _styledBlock(node, BlockKind.heading5);
        return;
      case 'h6':
        _styledBlock(node, BlockKind.heading6);
        return;

      case 'ul':
      case 'ol':
      case 'menu':
        _flush(BlockKind.paragraph);
        _visitChildren(node);
        _flush(BlockKind.paragraph);
        return;

      case 'li':
        _flush(BlockKind.paragraph);
        _runs.add(RawRun('• ', bold: _bold, italic: _italic));
        _visitChildren(node);
        _flush(BlockKind.listItem);
        return;

      case 'pre':
        _flush(BlockKind.paragraph);
        _preserveWhitespace = true;
        _monospace = true;
        _visitChildren(node);
        _monospace = false;
        _preserveWhitespace = false;
        _flush(BlockKind.code);
        return;

      case 'b':
      case 'strong':
        _withStyle(node, () => _bold = true, () => _bold = false);
        return;

      case 'i':
      case 'em':
      case 'cite':
      case 'dfn':
        _withStyle(node, () => _italic = true, () => _italic = false);
        return;

      case 'u':
      case 'ins':
        _withStyle(node, () => _underline = true, () => _underline = false);
        return;

      case 'code':
      case 'kbd':
      case 'samp':
      case 'tt':
        _withStyle(node, () => _monospace = true, () => _monospace = false);
        return;

      case 'a':
        final href = node.attributes['href'];
        if (href != null && !href.startsWith('#') && !href.startsWith('javascript:')) {
          _withStyle(node, () => _link = true, () => _link = false);
        } else {
          _visitChildren(node);
        }
        return;

      case 'sup':
      case 'sub':
      case 'span':
      case 'small':
      case 'abbr':
      case 'mark':
      case 'time':
      case 'q':
      case 's':
      case 'del':
      default:
        _visitChildren(node);
        return;
    }
  }

  void _styledBlock(dom.Element node, BlockKind kind) {
    _flush(BlockKind.paragraph);
    _visitChildren(node);
    _flush(kind);
  }

  void _withStyle(dom.Node node, void Function() enter, void Function() exit) {
    enter();
    _visitChildren(node);
    exit();
  }

  // ------------------------------------------------------------------- text

  void _addText(String raw) {
    if (raw.isEmpty) return;
    var text = raw.replaceAll('\uFEFF', '').replaceAll('\u200B', '');
    if (_preserveWhitespace) {
      // Keep line breaks, normalise the rest.
      text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    } else {
      text = text.replaceAll(RegExp(r'[\t\r\n ]+'), ' ');
    }
    if (text.isEmpty) return;
    _runs.add(_run(text));
  }

  RawRun _run(String text) => RawRun(
    text,
    bold: _bold,
    italic: _italic,
    underline: _underline,
    monospace: _monospace,
    link: _link,
  );

  void _flush(BlockKind kind) {
    if (_runs.isEmpty) return;
    final runs = _normalize(_runs);
    _runs.clear();
    if (runs.isEmpty) return;

    final length = runs.fold<int>(0, (sum, run) => sum + run.text.length);
    if (length == 0) return;

    _blocks.add(RawTextBlock(runs: runs, kind: kind, offset: _offset));
    _offset += length + 1;
  }

  List<RawRun> _normalize(List<RawRun> runs) {
    final output = <RawRun>[];
    var previousWasSpace = true;

    for (final run in runs) {
      final buffer = StringBuffer();
      for (final rune in run.text.runes) {
        if (rune == 0x0A) {
          buffer.write('\n');
          previousWasSpace = true;
          continue;
        }
        final isSpace =
            rune == 0x20 || rune == 0x09 || rune == 0x0D || rune == 0xA0;
        if (isSpace) {
          if (previousWasSpace) continue;
          previousWasSpace = true;
          buffer.write(' ');
        } else {
          previousWasSpace = false;
          buffer.write(String.fromCharCode(rune));
        }
      }

      final text = buffer.toString();
      if (text.isEmpty) continue;

      if (output.isNotEmpty && output.last.sameStyle(run)) {
        output[output.length - 1] = output.last.withText(output.last.text + text);
      } else {
        output.add(run.withText(text));
      }
    }

    if (output.isNotEmpty) {
      final last = output.last;
      final trimmed = last.text.replaceFirst(RegExp(r'[ ]+$'), '');
      if (trimmed.isEmpty) {
        output.removeLast();
      } else {
        output[output.length - 1] = last.withText(trimmed);
      }
    }
    return output;
  }

  // ----------------------------------------------------------------- images

  void _addImage(dom.Element node) {
    if (imageBudget <= 0) return;
    final src = node.attributes['src'] ?? node.attributes['xlink:href'];
    if (src == null || src.isEmpty) return;

    Uint8List? bytes;
    if (src.startsWith('data:')) {
      bytes = _decodeDataUri(src);
    } else {
      bytes = archive.read(resolveArchivePath(basePath, src));
    }
    if (bytes == null || bytes.length < 512) return;
    if (bytes.length > imageBudget) return;

    final size = imageDimensions(bytes);
    final width = (size?.width ?? 0).toDouble();
    final height = (size?.height ?? 0).toDouble();
    if (width < 32 || height < 32) return;

    imageBudget -= bytes.length;
    _blocks.add(RawImageBlock(bytes: bytes, width: width, height: height));
  }

  Uint8List? _decodeDataUri(String value) {
    try {
      final comma = value.indexOf(',');
      if (comma < 0) return null;
      final header = value.substring(0, comma);
      final payload = value.substring(comma + 1);
      if (header.contains(';base64')) {
        return base64Decode(payload);
      }
      return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
    } catch (_) {
      return null;
    }
  }
}
