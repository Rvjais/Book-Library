import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _db;

  Future<Database> get instance async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'libready.db');
    final opened = await openDatabase(
      path,
      version: 5,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: (db) async {
        // Ensure schema columns are present even if previous upgrade steps were interrupted.
        await _ensureColumns(db);
      },
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    _db = opened;
    return opened;
  }

  Future<void> _ensureColumns(Database db) async {
    await _addBookColumnQuietly(db, 'is_shared', 'INTEGER NOT NULL DEFAULT 0');
    await _addBookColumnQuietly(db, 'content_hash', 'TEXT NOT NULL DEFAULT ""');
    await _addBookColumnQuietly(db, 'description', 'TEXT');
    await _addBookColumnQuietly(db, 'language', 'TEXT');
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL,
        cover_path TEXT NOT NULL DEFAULT '',
        format TEXT NOT NULL DEFAULT 'pdf',
        file_size INTEGER NOT NULL DEFAULT 0,
        file_hash TEXT NOT NULL DEFAULT '',
        page_count INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL DEFAULT 0,
        last_opened_at INTEGER NOT NULL DEFAULT 0,
        progress REAL NOT NULL DEFAULT 0,
        position TEXT NOT NULL DEFAULT '{}',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_finished INTEGER NOT NULL DEFAULT 0,
        is_shared INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL DEFAULT '',
        description TEXT,
        language TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE bookmarks (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL DEFAULT 0,
        page INTEGER NOT NULL DEFAULT 0,
        offset INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        snippet TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_bookmarks_book ON bookmarks (book_id, page)',
    );

    await _createHighlightsTable(db);
  }

  Future<void> _createHighlightsTable(
    Database db, {
    bool includeAnchors = true,
  }) async {
    await db.execute('''
      CREATE TABLE highlights (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        page INTEGER NOT NULL DEFAULT 0,
        chapter INTEGER NOT NULL DEFAULT 0,
        ${includeAnchors ? 'chapter_offset INTEGER NOT NULL DEFAULT 0,' : ''}
        ${includeAnchors ? 'length INTEGER NOT NULL DEFAULT 0,' : ''}
        text TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        color INTEGER NOT NULL DEFAULT 0xFFFFEB3B,
        created_at INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');
    if (includeAnchors) {
      await _createHighlightAnchorIndex(db);
    }
  }

  Future<void> _createHighlightAnchorIndex(Database db) async {
    // IF NOT EXISTS matters for the v2 -> v3 path, where the page index is
    // already present.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_highlights_book '
      'ON highlights (book_id, page)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_highlights_anchor '
      'ON highlights (book_id, chapter, chapter_offset)',
    );
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createHighlightsTable(db, includeAnchors: false);
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE highlights '
        'ADD COLUMN chapter_offset INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE highlights ADD COLUMN length INTEGER NOT NULL DEFAULT 0',
      );
      await _createHighlightAnchorIndex(db);
    }
    if (oldVersion < 4) {
      await _addBookColumnQuietly(db, 'is_shared', 'INTEGER NOT NULL DEFAULT 0');
      await _addBookColumnQuietly(db, 'content_hash', 'TEXT NOT NULL DEFAULT ""');
    }
    if (oldVersion < 5) {
      await _addBookColumnQuietly(db, 'is_shared', 'INTEGER NOT NULL DEFAULT 0');
      await _addBookColumnQuietly(db, 'content_hash', 'TEXT NOT NULL DEFAULT ""');
    }
  }

  Future<void> _addBookColumnQuietly(
    Database db,
    String column,
    String type,
  ) async {
    try {
      await db.execute('ALTER TABLE books ADD COLUMN $column $type');
    } catch (_) {
      // Column may already exist
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
