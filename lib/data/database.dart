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
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
    );
    _db = opened;
    return opened;
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
        description TEXT,
        language TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
