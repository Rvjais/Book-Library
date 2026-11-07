import 'dart:convert';

enum BookFormat { pdf, epub }

extension BookFormatX on BookFormat {
  String get dbValue => this == BookFormat.epub ? 'epub' : 'pdf';
  String get label => this == BookFormat.epub ? 'EPUB' : 'PDF';

  static BookFormat parse(String? value) =>
      value == 'epub' ? BookFormat.epub : BookFormat.pdf;
}

/// Where the reader left off.
///
/// - [chapter] is only meaningful for EPUB (spine index).
/// - [page] is the absolute page index at the time of saving.
/// - [offset] is the character offset inside the EPUB chapter so the position
///   survives font-size changes.
class ReadingPosition {
  const ReadingPosition({this.chapter = 0, this.page = 0, this.offset = 0});

  final int chapter;
  final int page;
  final int offset;

  factory ReadingPosition.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const ReadingPosition();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ReadingPosition(
          chapter: (decoded['c'] as num?)?.toInt() ?? 0,
          page: (decoded['p'] as num?)?.toInt() ?? 0,
          offset: (decoded['o'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {
      // Corrupt position, start from the beginning.
    }
    return const ReadingPosition();
  }

  String toJson() => jsonEncode({'c': chapter, 'p': page, 'o': offset});

  @override
  String toString() => 'ReadingPosition(c: $chapter, p: $page, o: $offset)';
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.coverPath,
    required this.format,
    required this.fileSize,
    required this.fileHash,
    required this.pageCount,
    required this.addedAt,
    required this.lastOpenedAt,
    required this.progress,
    required this.position,
    required this.isFavorite,
    required this.isFinished,
    this.description,
    this.language,
  });

  final int id;
  final String title;
  final String author;
  final String filePath;
  final String coverPath;
  final BookFormat format;
  final int fileSize;
  final String fileHash;

  /// PDF: number of pages. EPUB: page count from the last pagination pass
  /// (falls back to the number of chapters before the book is opened).
  final int pageCount;
  final int addedAt;
  final int lastOpenedAt;
  final double progress;
  final String position;
  final bool isFavorite;
  final bool isFinished;
  final String? description;
  final String? language;

  bool get isEpub => format == BookFormat.epub;
  bool get isPdf => format == BookFormat.pdf;
  bool get hasCover => coverPath.isNotEmpty;
  bool get hasStarted => progress > 0.005;
  int get shelfDate => lastOpenedAt > 0 ? lastOpenedAt : addedAt;
  ReadingPosition get readingPosition => ReadingPosition.fromJson(position);

  factory Book.fromRow(Map<String, Object?> row) {
    return Book(
      id: row['id'] as int,
      title: (row['title'] as String?) ?? 'Untitled',
      author: (row['author'] as String?) ?? '',
      filePath: (row['file_path'] as String?) ?? '',
      coverPath: (row['cover_path'] as String?) ?? '',
      format: BookFormatX.parse(row['format'] as String?),
      fileSize: (row['file_size'] as int?) ?? 0,
      fileHash: (row['file_hash'] as String?) ?? '',
      pageCount: (row['page_count'] as int?) ?? 0,
      addedAt: (row['added_at'] as int?) ?? 0,
      lastOpenedAt: (row['last_opened_at'] as int?) ?? 0,
      progress: (row['progress'] as num?)?.toDouble() ?? 0,
      position: (row['position'] as String?) ?? '{}',
      isFavorite: ((row['is_favorite'] as int?) ?? 0) == 1,
      isFinished: ((row['is_finished'] as int?) ?? 0) == 1,
      description: row['description'] as String?,
      language: row['language'] as String?,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'author': author,
    'file_path': filePath,
    'cover_path': coverPath,
    'format': format.dbValue,
    'file_size': fileSize,
    'file_hash': fileHash,
    'page_count': pageCount,
    'added_at': addedAt,
    'last_opened_at': lastOpenedAt,
    'progress': progress,
    'position': position,
    'is_favorite': isFavorite ? 1 : 0,
    'is_finished': isFinished ? 1 : 0,
    'description': description,
    'language': language,
  };

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? filePath,
    String? coverPath,
    BookFormat? format,
    int? fileSize,
    String? fileHash,
    int? pageCount,
    int? addedAt,
    int? lastOpenedAt,
    double? progress,
    String? position,
    bool? isFavorite,
    bool? isFinished,
    String? description,
    String? language,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      format: format ?? this.format,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      pageCount: pageCount ?? this.pageCount,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      progress: progress ?? this.progress,
      position: position ?? this.position,
      isFavorite: isFavorite ?? this.isFavorite,
      isFinished: isFinished ?? this.isFinished,
      description: description ?? this.description,
      language: language ?? this.language,
    );
  }

  Book withId(int newId) => copyWith(id: newId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Book(id: $id, title: "$title")';
}

/// A user note on a specific point in a book.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.page,
    required this.offset,
    required this.note,
    required this.snippet,
    required this.createdAt,
  });

  final int id;
  final int bookId;
  final int chapter;
  final int page;
  final int offset;
  final String note;
  final String snippet;
  final int createdAt;

  String get displayTitle {
    if (note.trim().isNotEmpty) return note.trim();
    if (snippet.trim().isNotEmpty) return snippet.trim();
    return 'Bookmark on page ${page + 1}';
  }

  ReadingPosition get position =>
      ReadingPosition(chapter: chapter, page: page, offset: offset);

  factory Bookmark.fromRow(Map<String, Object?> row) {
    return Bookmark(
      id: row['id'] as int,
      bookId: row['book_id'] as int,
      chapter: (row['chapter'] as int?) ?? 0,
      page: (row['page'] as int?) ?? 0,
      offset: (row['offset'] as int?) ?? 0,
      note: (row['note'] as String?) ?? '',
      snippet: (row['snippet'] as String?) ?? '',
      createdAt: (row['created_at'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toRow({bool includeId = true}) {
    final map = <String, Object?>{
      'book_id': bookId,
      'chapter': chapter,
      'page': page,
      'offset': offset,
      'note': note,
      'snippet': snippet,
      'created_at': createdAt,
    };
    if (includeId) map['id'] = id;
    return map;
  }

  Bookmark copyWith({
    int? id,
    int? bookId,
    int? chapter,
    int? page,
    int? offset,
    String? note,
    String? snippet,
    int? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapter: chapter ?? this.chapter,
      page: page ?? this.page,
      offset: offset ?? this.offset,
      note: note ?? this.note,
      snippet: snippet ?? this.snippet,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
