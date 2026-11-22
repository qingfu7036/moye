/// Ordered schema migrations. Never edit an already released migration; append
/// a new one and bump [librarySchemaVersion].
const librarySchemaVersion = 5;

const libraryMigrations = <int, List<String>>{
  1: [
    '''
    CREATE TABLE books (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      author TEXT NOT NULL DEFAULT '',
      format TEXT NOT NULL,
      original_file_name TEXT NOT NULL,
      relative_path TEXT NOT NULL UNIQUE,
      file_hash TEXT NOT NULL UNIQUE,
      file_size INTEGER NOT NULL CHECK (file_size >= 0),
      cover_path TEXT,
      status TEXT NOT NULL DEFAULT 'notStarted',
      added_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_opened_at INTEGER,
      metadata_source TEXT NOT NULL DEFAULT 'file_name'
    )
    ''',
    'CREATE INDEX idx_books_title ON books(title COLLATE NOCASE)',
    'CREATE INDEX idx_books_author ON books(author COLLATE NOCASE)',
    'CREATE INDEX idx_books_status ON books(status)',
    'CREATE INDEX idx_books_added_at ON books(added_at DESC)',
    'CREATE INDEX idx_books_last_opened ON books(last_opened_at DESC)',
    '''
    CREATE TABLE shelves (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE book_shelves (
      book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      shelf_id TEXT NOT NULL REFERENCES shelves(id) ON DELETE CASCADE,
      added_at INTEGER NOT NULL,
      PRIMARY KEY (book_id, shelf_id)
    )
    ''',
    '''
    CREATE TABLE tags (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL UNIQUE,
      color TEXT NOT NULL DEFAULT 'yellow',
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE book_tags (
      book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      added_at INTEGER NOT NULL,
      PRIMARY KEY (book_id, tag_id)
    )
    ''',
    '''
    CREATE TABLE reading_progress (
      book_id TEXT PRIMARY KEY NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      anchor_json TEXT,
      percent REAL NOT NULL DEFAULT 0 CHECK (percent >= 0 AND percent <= 1),
      mode TEXT,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
  ],
  2: [
    '''
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY NOT NULL,
      book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      kind TEXT NOT NULL DEFAULT 'region',
      page_number INTEGER,
      chapter_index INTEGER,
      block_index INTEGER,
      rect_json TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      quote TEXT NOT NULL DEFAULT '',
      image_path TEXT,
      color TEXT NOT NULL DEFAULT 'yellow',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_annotations_book ON annotations(book_id, created_at DESC)',
    'CREATE INDEX idx_annotations_note ON annotations(note COLLATE NOCASE)',
  ],
  3: [
    '''
    CREATE TABLE speech_progress (
      book_id TEXT PRIMARY KEY NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      anchor_json TEXT NOT NULL,
      percent REAL NOT NULL DEFAULT 0 CHECK (percent >= 0 AND percent <= 1),
      mode TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_speech_progress_updated ON speech_progress(updated_at DESC)',
  ],
  4: [
    '''
    CREATE TABLE bookmarks (
      id TEXT PRIMARY KEY NOT NULL,
      book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      page_number INTEGER,
      chapter_index INTEGER,
      block_index INTEGER,
      page_offset REAL NOT NULL DEFAULT 0,
      label TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_bookmarks_book ON bookmarks(book_id, created_at DESC)',
  ],
  5: [
    '''
    CREATE TABLE annotations_v5 (
      id TEXT PRIMARY KEY NOT NULL,
      book_id TEXT REFERENCES books(id) ON DELETE SET NULL,
      book_title TEXT NOT NULL DEFAULT '',
      kind TEXT NOT NULL DEFAULT 'region',
      page_number INTEGER,
      chapter_index INTEGER,
      block_index INTEGER,
      rect_json TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      quote TEXT NOT NULL DEFAULT '',
      image_path TEXT,
      color TEXT NOT NULL DEFAULT 'yellow',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    INSERT INTO annotations_v5
      (id, book_id, book_title, kind, page_number, chapter_index, block_index,
       rect_json, note, quote, image_path, color, created_at, updated_at)
    SELECT a.id, a.book_id,
      COALESCE((SELECT b.title FROM books b WHERE b.id = a.book_id), ''),
      a.kind, a.page_number, a.chapter_index, a.block_index,
      a.rect_json, a.note, a.quote, a.image_path, a.color,
      a.created_at, a.updated_at
    FROM annotations a
    ''',
    'DROP TABLE annotations',
    'ALTER TABLE annotations_v5 RENAME TO annotations',
    'CREATE INDEX idx_annotations_book ON annotations(book_id, created_at DESC)',
    'CREATE INDEX idx_annotations_note ON annotations(note COLLATE NOCASE)',
  ],
};
