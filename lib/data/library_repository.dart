import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/formatting.dart';
import '../core/ids.dart';
import '../epub/epub_parser.dart';
import '../services/cover_service.dart';
import 'book_storage.dart';
import 'database.dart';
import 'models.dart';
import 'settings_repository.dart';

class ImportOutcome {
  const ImportOutcome({
    required this.imported,
    required this.duplicates,
    required this.failed,
  });

  final int imported;
  final int duplicates;
  final int failed;

  bool get hadFailures => failed > 0;

  String get message {
    final parts = <String>[];
    if (imported > 0) parts.add('$imported added');
    if (duplicates > 0) parts.add('$duplicates already in library');
    if (failed > 0) parts.add('$failed could not be read');
    if (parts.isEmpty) return 'Nothing to import';
    return parts.join(' · ');
  }
}

class _Metadata {
  const _Metadata({
    this.title,
    this.author,
    this.description,
    this.language,
    this.pageCount = 0,
    this.cover,
  });

  final String? title;
  final String? author;
  final String? description;
  final String? language;
  final int pageCount;
  final Uint8List? cover;
}

enum _ImportStatus { imported, duplicate, failed }

class _ImportResult {
  const _ImportResult._(this.status, this.book);
  const _ImportResult.imported(Book value)
      : this._(_ImportStatus.imported, value);
  const _ImportResult.duplicate() : this._(_ImportStatus.duplicate, null);
  const _ImportResult.failed() : this._(_ImportStatus.failed, null);

  final _ImportStatus status;
  final Book? book;
}

class LibraryRepository extends ChangeNotifier {
  LibraryRepository({
    required this.settings,
    BookStorage? storage,
    CoverService covers = const CoverService(),
  })  : storage = storage ?? BookStorage(),
        _covers = covers {
    _sort = settings.sortMode;
  }

  final SettingsRepository settings;
  final BookStorage storage;
  final CoverService _covers;
  final AppDatabase _database = AppDatabase();

  List<Book> _books = const <Book>[];
  bool _loading = true;
  Object? _lastError;
  String _query = '';
  late SortMode _sort;
  LibraryFilter _filter = LibraryFilter.all;

  bool get isLoading => _loading;
  Object? get lastError => _lastError;
  List<Book> get books => List<Book>.unmodifiable(_books);
  int get bookCount => _books.length;

  SortMode get sortMode => _sort;
  LibraryFilter get filter => _filter;
  String get query => _query;

  int get readingCount =>
      _books.where((book) => book.hasStarted && !book.isFinished).length;

  int get finishedCount => _books.where((book) => book.isFinished).length;

  Book? get continueReading {
    final candidates =
        _books.where((book) => book.hasStarted && !book.isFinished).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return candidates.first;
  }

  List<Book> get inProgress {
    final list =
        _books.where((book) => book.hasStarted && !book.isFinished).toList();
    list.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return list;
  }

  List<Book> get visibleBooks {
    final search = _query.trim().toLowerCase();
    var list = _books.where((book) {
      switch (_filter) {
        case LibraryFilter.all:
          break;
        case LibraryFilter.reading:
          if (!book.hasStarted || book.isFinished) return false;
          break;
        case LibraryFilter.finished:
          if (!book.isFinished) return false;
          break;
        case LibraryFilter.favorites:
          if (!book.isFavorite) return false;
          break;
      }
      if (search.isEmpty) return true;
      return book.title.toLowerCase().contains(search) ||
          book.author.toLowerCase().contains(search) ||
          (book.description?.toLowerCase().contains(search) ?? false) ||
          (book.language?.toLowerCase().contains(search) ?? false);
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case SortMode.recent:
          final opened = b.lastOpenedAt.compareTo(a.lastOpenedAt);
          return opened != 0 ? opened : b.addedAt.compareTo(a.addedAt);
        case SortMode.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case SortMode.author:
          final byAuthor =
              a.author.toLowerCase().compareTo(b.author.toLowerCase());
          return byAuthor != 0
              ? byAuthor
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case SortMode.added:
          return b.addedAt.compareTo(a.addedAt);
        case SortMode.size:
          return b.fileSize.compareTo(a.fileSize);
      }
    });
    return list;
  }

  Future<void> init() async {
    try {
      final db = await _database.instance;
      final rows = await db.query('books');
      _books = rows.map(Book.fromRow).toList();
    } catch (error) {
      _lastError = error;
      debugPrint('Could not load library: $error');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> reload() async {
    _loading = true;
    notifyListeners();
    await init();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void setFilter(LibraryFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setSortMode(SortMode value) {
    if (_sort == value) return;
    _sort = value;
    unawaited(settings.setSortMode(value));
    notifyListeners();
  }

  Book? bookById(int id) {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  // --------------------------------------------------------------- importing

  Future<ImportOutcome> importFiles(
    List<PlatformFile> files, {
    void Function(int done, int total, String name)? onProgress,
  }) async {
    var imported = 0;
    var duplicates = 0;
    var failed = 0;
    final total = files.length;

    for (var index = 0; index < total; index++) {
      final file = files[index];
      onProgress?.call(index, total, file.name);
      try {
        final result = await _importOne(file);
        switch (result.status) {
          case _ImportStatus.imported:
            imported++;
            break;
          case _ImportStatus.duplicate:
            duplicates++;
            break;
          case _ImportStatus.failed:
            failed++;
            break;
        }
      } catch (error) {
        failed++;
        debugPrint('Import failed for ${file.name}: $error');
      }
      onProgress?.call(index + 1, total, file.name);
    }

    return ImportOutcome(
      imported: imported,
      duplicates: duplicates,
      failed: failed,
    );
  }

  Future<_ImportResult> _importOne(PlatformFile file) async {
    var extension = (file.extension ?? '').toLowerCase();
    if (extension.isEmpty) {
      final dot = file.name.lastIndexOf('.');
      if (dot >= 0) extension = file.name.substring(dot + 1).toLowerCase();
    }
    if (extension != 'pdf' && extension != 'epub') {
      return const _ImportResult.failed();
    }

    final storageId = newId();
    String? path;
    var coverPath = '';
    try {
      path = await storage.importPickedFile(file, storageId, extension);
      final stored = File(path);
      if (!await stored.exists() || await stored.length() < 512) {
        await storage.deleteQuietly(path);
        return const _ImportResult.failed();
      }

      final fingerprint = await fileFingerprint(stored);
      for (final existing in _books) {
        if (existing.fileHash == fingerprint) {
          await storage.deleteQuietly(path);
          return const _ImportResult.duplicate();
        }
      }

      final isPdf = extension == 'pdf';
      final meta = isPdf ? await _readPdf(path) : await _readEpub(path);

      final title = (meta.title ?? '').trim().isNotEmpty
          ? meta.title!.trim()
          : titleFromFileName(file.name);

      if (meta.cover != null && meta.cover!.isNotEmpty) {
        coverPath = await _covers.save(storage, storageId, meta.cover) ?? '';
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final book = Book(
        id: 0,
        title: title,
        author: (meta.author ?? '').trim(),
        filePath: path,
        coverPath: coverPath,
        format: isPdf ? BookFormat.pdf : BookFormat.epub,
        fileSize: await stored.length(),
        fileHash: fingerprint,
        isShared: false,
        contentHash: fingerprint,
        pageCount: meta.pageCount,
        addedAt: now,
        lastOpenedAt: 0,
        progress: 0,
        position: '{}',
        isFavorite: false,
        isFinished: false,
        description: meta.description,
        language: meta.language,
      );

      final db = await _database.instance;
      final row = book.toRow()..remove('id');
      final insertedId = await db.insert('books', row);
      final saved = book.withId(insertedId);

      _books = <Book>[saved, ..._books];
      notifyListeners();
      return _ImportResult.imported(saved);
    } catch (error) {
      debugPrint('Could not import ${file.name}: $error');
      if (path != null) await storage.deleteQuietly(path);
      if (coverPath.isNotEmpty) await storage.deleteQuietly(coverPath);
      return const _ImportResult.failed();
    }
  }

  Future<_Metadata> _readPdf(String path) async {
    PdfDocument? document;
    Uint8List? cover;
    var pages = 0;
    try {
      document = await PdfDocument.openFile(path);
      pages = document.pages.length;
      if (pages > 0) {
        final page = document.pages[0];
        final ratio = page.width <= 0 ? 1.5 : page.height / page.width;
        final rendered = await page.render(
          width: 900,
          height: (900 * ratio).round(),
        );
        if (rendered != null) {
          try {
            final uiImage = await rendered.createImage();
            final byteData = await uiImage.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (byteData != null) {
              cover = byteData.buffer.asUint8List();
            }
          } finally {
            rendered.dispose();
          }
        }
      }
    } finally {
      await document?.dispose();
    }
    return _Metadata(pageCount: pages, cover: cover);
  }

  Future<_Metadata> _readEpub(String path) async {
    final epub = await EpubParser.open(path);
    return _Metadata(
      title: epub.title,
      author: epub.author,
      description: epub.description,
      language: epub.language,
      pageCount: epub.chapters.length,
      cover: epub.coverBytes,
    );
  }

  // ------------------------------------------------------------ reading state

  Future<void> touchOpened(Book book) async {
    final current = bookById(book.id) ?? book;
    final updated = current.copyWith(
      lastOpenedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  Future<void> saveProgress(
    Book book, {
    required ReadingPosition position,
    required int pageCount,
    required double progress,
  }) async {
    final current = bookById(book.id) ?? book;
    final now = DateTime.now().millisecondsSinceEpoch;
    final clamped = progress.clamp(0.0, 1.0);
    final updated = current.copyWith(
      position: position.toJson(),
      pageCount: pageCount,
      progress: clamped,
      lastOpenedAt: now,
      isFinished: current.isFinished || clamped >= 0.995,
    );
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  Future<void> setFavorite(Book book, bool value) async {
    final current = bookById(book.id) ?? book;
    if (current.isFavorite == value) return;
    final updated = current.copyWith(isFavorite: value);
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  Future<void> setFinished(Book book, bool value) async {
    final current = bookById(book.id) ?? book;
    // Marking a book un-finished keeps the reader where they were. Only the
    // finished flag and progress need to change, never the saved position.
    final updated = current.copyWith(
      isFinished: value,
      progress: value
          ? 1
          : (current.progress >= 0.995 ? 0.99 : current.progress),
    );
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  /// Puts a finished book back at the first page so it can be read again.
  Future<void> restartReading(Book book) async {
    final current = bookById(book.id) ?? book;
    final updated = current.copyWith(
      progress: 0,
      position: const ReadingPosition().toJson(),
      isFinished: false,
      lastOpenedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  Future<void> updateMetadata(Book book,
      {String? title, String? author}) async {
    final current = bookById(book.id) ?? book;
    final updated = current.copyWith(
      title: (title ?? current.title).trim().isEmpty
          ? current.title
          : title!.trim(),
      author: (author ?? current.author).trim(),
    );
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  Future<void> updateCover(Book book, String coverPath) async {
    final current = bookById(book.id) ?? book;
    final updated = current.copyWith(coverPath: coverPath);
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  /// Replaces the cover with artwork picked from the device.
  Future<bool> setCoverFromBytes(Book book, Uint8List bytes) async {
    final current = bookById(book.id) ?? book;
    final path = await _covers.save(storage, '${current.id}', bytes);
    if (path == null) return false;
    final previous = current.coverPath;
    // Point the row at the new file first; only then remove the old one so a
    // database failure can never leave the book referring to a deleted cover.
    await updateCover(current, path);
    await storage.deleteQuietly(previous);
    return true;
  }

  /// Rebuilds the cover from the first page (PDF) or package cover (EPUB).
  Future<bool> regenerateCover(Book book) async {
    try {
      final meta = book.isEpub
          ? await _readEpub(book.filePath)
          : await _readPdf(book.filePath);
      if (meta.cover == null) return false;
      final path = await _covers.save(storage, newId(), meta.cover);
      if (path == null) return false;
      final previous = book.coverPath;
      await updateCover(book, path);
      await storage.deleteQuietly(previous);
      return true;
    } catch (error) {
      debugPrint('Could not regenerate cover: $error');
      return false;
    }
  }

  Future<void> deleteBook(Book book) async {
    final db = await _database.instance;
    await db.delete('books', where: 'id = ?', whereArgs: [book.id]);
    await storage.deleteQuietly(book.filePath);
    await storage.deleteQuietly(book.coverPath);
    _books = _books.where((item) => item.id != book.id).toList();
    notifyListeners();
  }

  Future<void> deleteEverything() async {
    final db = await _database.instance;
    await db.delete('highlights');
    await db.delete('bookmarks');
    await db.delete('books');
    _books = const <Book>[];
    notifyListeners();
    await storage.deleteEverything();
  }

  /// Drops entries whose file has vanished (e.g. restored from a backup).
  Future<int> pruneMissingFiles() async {
    final missing = <Book>[];
    for (final book in _books) {
      try {
        if (!await File(book.filePath).exists()) missing.add(book);
      } catch (_) {
        missing.add(book);
      }
    }
    for (final book in missing) {
      await deleteBook(book);
    }
    return missing.length;
  }

  Future<int> storageBytes() => storage.usedBytes();

  /// Import a file that was already downloaded (e.g. from P2P transfer) into
  /// the library. The file must already exist at [filePath].
  Future<Book> importDownloadedBook({
    required int id,
    required String title,
    required String author,
    required String filePath,
    required String coverPath,
    required BookFormat format,
    required int fileSize,
    required String fileHash,
    required bool isShared,
    required String contentHash,
    String? description,
    String? language,
  }) async {
    final stored = File(filePath);
    if (!await stored.exists()) {
      throw StateError('Downloaded file not found: $filePath');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final book = Book(
      id: id,
      title: title,
      author: author,
      filePath: filePath,
      coverPath: coverPath,
      format: format,
      fileSize: fileSize,
      fileHash: fileHash,
      isShared: isShared,
      contentHash: contentHash,
      pageCount: 0,
      addedAt: now,
      lastOpenedAt: 0,
      progress: 0,
      position: '{}',
      isFavorite: false,
      isFinished: false,
      description: description,
      language: language,
    );

    final db = await _database.instance;
    final row = book.toRow()..remove('id');
    final insertedId = await db.insert('books', row);
    final saved = book.withId(insertedId);

    _books = <Book>[saved, ..._books];
    notifyListeners();
    return saved;
  }

  /// Enable or disable sharing for a book. When disabled, the P2P service
  /// should withdraw the advertisement.
  Future<void> setBookSharing(Book book, bool value) async {
    final current = bookById(book.id) ?? book;
    if (current.isShared == value) return;
    final updated = current.copyWith(isShared: value);
    await _persist(updated);
    _replace(updated);
    notifyListeners();
  }

  // ---------------------------------------------------------------- bookmarks

  Future<List<Bookmark>> bookmarksFor(int bookId) async {
    final db = await _database.instance;
    final rows = await db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<Bookmark> addBookmark({
    required Book book,
    required ReadingPosition position,
    required String snippet,
    String note = '',
  }) async {
    final db = await _database.instance;
    final bookmark = Bookmark(
      id: 0,
      bookId: book.id,
      chapter: position.chapter,
      page: position.page,
      offset: position.offset,
      note: note,
      snippet: snippet,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final row = bookmark.toRow(includeId: false);
    final id = await db.insert('bookmarks', row);
    return Bookmark.fromRow(<String, Object?>{...row, 'id': id});
  }

  Future<void> updateBookmarkNote(Bookmark bookmark, String note) async {
    final db = await _database.instance;
    await db.update(
      'bookmarks',
      {'note': note},
      where: 'id = ?',
      whereArgs: [bookmark.id],
    );
  }

  Future<void> deleteBookmark(int bookmarkId) async {
    final db = await _database.instance;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [bookmarkId]);
  }

  // ---------------------------------------------------------------- highlights

  Future<List<BookHighlight>> highlightsFor(int bookId) async {
    final db = await _database.instance;
    final rows = await db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page ASC, created_at DESC',
    );
    return rows.map(BookHighlight.fromRow).toList();
  }

  Future<BookHighlight> addHighlight({
    required Book book,
    required int page,
    int chapter = 0,
    int chapterOffset = 0,
    int length = 0,
    required String text,
    String note = '',
    int color = 0xFFFFEB3B,
  }) async {
    final db = await _database.instance;
    final highlight = BookHighlight(
      id: 0,
      bookId: book.id,
      page: page,
      chapter: chapter,
      chapterOffset: chapterOffset,
      length: length,
      text: text,
      note: note,
      color: color,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final row = highlight.toRow(includeId: false);
    final id = await db.insert('highlights', row);
    return BookHighlight.fromRow(<String, Object?>{...row, 'id': id});
  }

  Future<void> updateHighlightNote(BookHighlight highlight, String note) async {
    final db = await _database.instance;
    await db.update(
      'highlights',
      {'note': note},
      where: 'id = ?',
      whereArgs: [highlight.id],
    );
  }

  Future<void> deleteHighlight(int highlightId) async {
    final db = await _database.instance;
    await db.delete('highlights', where: 'id = ?', whereArgs: [highlightId]);
  }

  // ------------------------------------------------------------------ helpers

  Future<void> _persist(Book book) async {
    final db = await _database.instance;
    await db.update(
      'books',
      book.toRow(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  void _replace(Book book) {
    _books = [
      for (final item in _books)
        if (item.id == book.id) book else item,
    ];
  }
}
