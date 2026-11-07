import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:libready/data/reader_settings.dart';
import 'package:libready/epub/epub_models.dart';
import 'package:libready/epub/epub_parser.dart';
import 'package:libready/reader/pagination/paginator.dart';

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 7 + y * 3) % 256,
        (x * 3 + y * 11) % 256,
        (x * 13 + y * 5) % 256,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Future<String> _writeEpub(Directory dir) async {
  final archive = Archive();

  void add(String name, String contents) {
    final bytes = Uint8List.fromList(contents.codeUnits);
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''');
  add('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">test-book</dc:identifier>
    <dc:title>The Test Book</dc:title>
    <dc:creator>Ada Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:description>A small book used to test parsing.</dc:description>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-image" href="cover.png" media-type="image/png" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''');
  add('OEBPS/nav.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Contents</title></head>
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="ch1.xhtml">Chapter One</a></li>
        <li><a href="ch2.xhtml">Chapter Two</a></li>
      </ol>
    </nav>
  </body>
</html>
''');
  add('OEBPS/ch1.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter One</title></head>
  <body>
    <h1>Chapter One</h1>
    <p>The <strong>first</strong> chapter has <em>some</em> formatted text.</p>
    <p><img src="cover.png" alt="A picture"/></p>
  </body>
</html>
''');
  add('OEBPS/ch2.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter Two</title></head>
  <body>
    <h2>Chapter Two</h2>
    <p>This is the second chapter of the test book.</p>
  </body>
</html>
''');
  archive.addFile(ArchiveFile.bytes('OEBPS/cover.png', _png(100, 150)));

  final encoded = ZipEncoder().encode(archive);
  final file = File('${dir.path}${Platform.pathSeparator}test.epub');
  await file.writeAsBytes(encoded, flush: true);
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('libready_epub_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('parses metadata, chapters, toc and cover from an EPUB', () async {
    final path = await _writeEpub(tempDir);
    final epub = await EpubParser.open(path);

    expect(epub.title, 'The Test Book');
    expect(epub.author, 'Ada Author');
    expect(epub.language, 'en');
    expect(epub.description, contains('small book'));
    expect(epub.coverBytes, isNotNull);
    expect(epub.coverBytes!.length, greaterThan(100));

    expect(epub.chapters, hasLength(2));
    expect(epub.chapters.first.title, 'Chapter One');
    expect(epub.chapters.first.plainText, contains('first chapter'));
    expect(
      epub.chapters.first.blocks.whereType<RawImageBlock>(),
      isNotEmpty,
    );
    expect(
      epub.chapters.first.blocks
          .whereType<RawTextBlock>()
          .expand((block) => block.runs)
          .any((run) => run.bold && run.text.contains('first')),
      isTrue,
    );

    expect(
        epub.toc.map((entry) => entry.title), ['Chapter One', 'Chapter Two']);
    expect(epub.toc.first.chapterIndex, 0);
    expect(epub.toc.last.chapterIndex, 1);
  });

  test('rejects a file that is not an EPUB', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}broken.epub');
    await file.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
    expect(
      () => EpubParser.open(file.path),
      throwsA(isA<EpubException>()),
    );
  });

  testWidgets('paginates a chapter into ordered pages', (tester) async {
    final words = List<String>.generate(1200, (index) => 'word$index');
    final text = words.join(' ');
    final chapter = EpubChapter(
      index: 0,
      path: 'chapter.xhtml',
      href: 'chapter.xhtml',
      title: 'A Long Chapter',
      blocks: [
        RawTextBlock(
          runs: [RawRun(text)],
          kind: BlockKind.paragraph,
          offset: 0,
        ),
        RawImageBlock(
          bytes: Uint8List.fromList([1, 2, 3]),
          width: 300,
          height: 200,
        ),
      ],
      plainText: text,
    );

    final paginator = Paginator(
      settings: const ReaderSettings(),
      width: 320,
      height: 480,
    );
    final pages = paginator.paginateChapter(chapter);

    expect(pages.length, greaterThan(1));
    expect(pages.every((page) => page.chapterIndex == 0), isTrue);
    expect(
        pages.every((page) => page.chapterTitle == 'A Long Chapter'), isTrue);
    expect(pages.first.startOffset, 0);
    for (var index = 1; index < pages.length; index++) {
      expect(
        pages[index].startOffset,
        greaterThanOrEqualTo(pages[index - 1].startOffset),
      );
      expect(
        pages[index].startOffset,
        greaterThanOrEqualTo(pages[index - 1].endOffset - 1),
      );
    }
    expect(pages.first.previewText, isNotEmpty);
  });
}
