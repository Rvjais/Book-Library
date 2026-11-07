import 'dart:typed_data';

enum BlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  quote,
  listItem,
  code,
  rule,
}

class RawRun {
  const RawRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.monospace = false,
    this.link = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool monospace;
  final bool link;

  RawRun withText(String value) => RawRun(
    value,
    bold: bold,
    italic: italic,
    underline: underline,
    monospace: monospace,
    link: link,
  );

  bool sameStyle(RawRun other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      monospace == other.monospace &&
      link == other.link;
}

class RawTextBlock {
  const RawTextBlock({
    required this.runs,
    required this.kind,
    required this.offset,
  });

  final List<RawRun> runs;
  final BlockKind kind;

  /// Character offset of this block inside the chapter's plain text.
  final int offset;

  String get text => runs.map((run) => run.text).join();
}

class RawImageBlock {
  const RawImageBlock({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final double width;
  final double height;

  double get aspect => height <= 0 ? 1.5 : width / height;
}

/// A decorative divider (`<hr>`), rendered as a thin rule on the page.
class RawRuleBlock {
  const RawRuleBlock();
}

class EpubChapter {
  const EpubChapter({
    required this.index,
    required this.path,
    required this.href,
    required this.title,
    required this.blocks,
    required this.plainText,
  });

  final int index;
  final String path;
  final String href;
  final String title;
  final List<Object> blocks; // RawTextBlock | RawImageBlock
  final String plainText;
}

class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.chapterIndex,
    this.level = 0,
  });

  final String title;
  final int chapterIndex;
  final int level;
}

class ParsedEpub {
  const ParsedEpub({
    required this.title,
    required this.author,
    required this.description,
    required this.language,
    required this.coverBytes,
    required this.chapters,
    required this.toc,
  });

  final String? title;
  final String? author;
  final String? description;
  final String? language;
  final Uint8List? coverBytes;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> toc;
}
