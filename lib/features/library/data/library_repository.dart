import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../../core/covers/book_cover_extractor.dart';
import '../../../core/database/library_database.dart';
import '../../../core/metadata/book_metadata_extractor.dart';
import '../../../core/models/annotation.dart';
import '../../../core/models/book.dart';
import '../../../core/models/bookmark.dart';
import '../../../core/models/speech_progress.dart';
import '../../../core/models/reading_progress.dart';
import '../../../core/storage/app_paths.dart';
import '../../../core/storage/book_file_store.dart';

enum ImportOutcomeKind { imported, duplicate, unsupported, failed }

class ImportOutcome {
  const ImportOutcome({
    required this.kind,
    required this.sourceName,
    this.book,
    this.message = '',
  });

  final ImportOutcomeKind kind;
  final String sourceName;
  final Book? book;
  final String message;
}

class LibraryRepository {
  LibraryRepository({
    required this.database,
    required this.paths,
    required this.files,
    this.metadataExtractor = const BookMetadataExtractor(),
    this.coverExtractor = const BookCoverExtractor(),
    this.uuid = const Uuid(),
  });

  final LibraryDatabase database;
  final AppPaths paths;
  final BookFileStore files;
  final BookMetadataExtractor metadataExtractor;
  final BookCoverExtractor coverExtractor;
  final Uuid uuid;

  Future<ImportOutcome> importFile(
    String sourcePath, {
    String? sourceName,
  }) async {
    final source = File(sourcePath);
    final resolvedName = sourceName ?? p.basename(source.path);
    final format = BookFormat.fromFileName(resolvedName);
    if (format == null) {
      return ImportOutcome(
        kind: ImportOutcomeKind.unsupported,
        sourceName: resolvedName,
        message: '不支持的文件格式',
      );
    }
    if (!await source.exists()) {
      return ImportOutcome(
        kind: ImportOutcomeKind.failed,
        sourceName: resolvedName,
        message: '源文件不存在',
      );
    }

    final id = uuid.v4();
    StoredBookFile? stored;
    String? coverPath;
    try {
      stored = await files.copyIntoLibrary(
        source: source.openRead(),
        id: id,
        format: format,
      );
      final existing = database.raw.select(
        'SELECT id, title, relative_path FROM books WHERE file_hash = ?',
        [stored.sha256],
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as String;
        final existingPath = existing.first['relative_path'] as String;
        final existingFile = paths.resolveRelative(existingPath);
        if (await existingFile.exists()) {
          await _deleteStoredQuietly(stored);
          return ImportOutcome(
            kind: ImportOutcomeKind.duplicate,
            sourceName: resolvedName,
            book: await findById(existingId),
            message: '书库中已存在同一文件',
          );
        }

        // The database row survived but its file is gone (crash, sync tool or
        // external deletion). Keep the old book identity and attach this fresh
        // copy instead of throwing away the only recoverable copy.
        final now = DateTime.now().toUtc();
        database.transaction(() {
          database.raw.execute(
            'UPDATE books SET relative_path = ?, file_size = ?, updated_at = ? WHERE id = ?',
            [
              stored!.relativePath,
              stored.size,
              now.millisecondsSinceEpoch,
              existingId,
            ],
          );
        });
        return ImportOutcome(
          kind: ImportOutcomeKind.imported,
          sourceName: resolvedName,
          book: await findById(existingId),
          message: '原文件缺失，已用新副本修复',
        );
      }

      final fallbackTitle = p.basenameWithoutExtension(resolvedName);
      final metadata = await metadataExtractor.extract(
        file: File(stored.absolutePath),
        format: format,
        fallbackTitle: fallbackTitle,
      );
      final now = DateTime.now().toUtc();
      coverPath = await coverExtractor.extract(
        file: File(stored.absolutePath),
        format: format,
        bookId: id,
        paths: paths,
      );
      final book = Book(
        id: id,
        title: metadata.title,
        author: metadata.author,
        format: format,
        originalFileName: resolvedName,
        relativePath: stored.relativePath,
        fileHash: stored.sha256,
        fileSize: stored.size,
        coverPath: coverPath,
        status: BookStatus.notStarted,
        addedAt: now,
        updatedAt: now,
        metadataSource: metadata.source,
      );

      try {
        database.transaction(() {
          database.raw.execute(
            '''
            INSERT INTO books (
              id, title, author, format, original_file_name, relative_path,
              file_hash, file_size, cover_path, status, added_at, updated_at,
              last_opened_at, metadata_source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
            ''',
            [
              book.id,
              book.title,
              book.author,
              book.format.name,
              book.originalFileName,
              book.relativePath,
              book.fileHash,
              book.fileSize,
              book.coverPath,
              book.status.name,
              book.addedAt.millisecondsSinceEpoch,
              book.updatedAt.millisecondsSinceEpoch,
              book.metadataSource,
            ],
          );
          database.raw.execute(
            '''
            INSERT INTO reading_progress (book_id, anchor_json, percent, mode, updated_at)
            VALUES (?, NULL, 0, NULL, ?)
            ''',
            [book.id, now.millisecondsSinceEpoch],
          );
        });
      } catch (error) {
        await _deleteStoredQuietly(stored);
        await _deleteCoverQuietly(coverPath);
        final duplicate = database.raw.select(
          'SELECT id, title FROM books WHERE file_hash = ?',
          [stored.sha256],
        );
        if (duplicate.isNotEmpty) {
          return ImportOutcome(
            kind: ImportOutcomeKind.duplicate,
            sourceName: resolvedName,
            book: await findById(duplicate.first['id'] as String),
            message: '书库中已存在同一文件',
          );
        }
        return ImportOutcome(
          kind: ImportOutcomeKind.failed,
          sourceName: resolvedName,
          message: '写入数据库失败：$error',
        );
      }
      return ImportOutcome(
        kind: ImportOutcomeKind.imported,
        sourceName: resolvedName,
        book: book,
        message: '已导入',
      );
    } catch (error) {
      if (stored != null) {
        await _deleteStoredQuietly(stored);
      }
      await _deleteCoverQuietly(coverPath);
      return ImportOutcome(
        kind: ImportOutcomeKind.failed,
        sourceName: resolvedName,
        message: '导入失败：$error',
      );
    }
  }

  /// Accepts a SAF/content-URI stream on Android as well as a desktop file.
  ///
  /// file_picker v13 exposes [PlatformFile.readAsByteStream], so the Phase 1
  /// import path does not depend on the platform returning a local path.
  Future<ImportOutcome> importStream({
    required String sourceName,
    required Stream<List<int>> source,
  }) async {
    final format = BookFormat.fromFileName(sourceName);
    if (format == null) {
      return ImportOutcome(
        kind: ImportOutcomeKind.unsupported,
        sourceName: sourceName,
        message: '不支持的文件格式',
      );
    }
    final temp = File(
      p.join(
        paths.cacheDir.path,
        'pick-${uuid.v4()}${p.extension(sourceName)}',
      ),
    );
    IOSink? sink;
    try {
      sink = temp.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in source) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return await importFile(temp.path, sourceName: sourceName);
    } catch (error) {
      return ImportOutcome(
        kind: ImportOutcomeKind.failed,
        sourceName: sourceName,
        message: '读取所选文件失败：$error',
      );
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // Do not let a broken sink mask the import result.
      }
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // A temp file in cache/ is safe to leave for the cleanup phase.
      }
    }
  }

  Future<List<Book>> listBooks([
    LibraryFilter filter = const LibraryFilter(),
  ]) async {
    final where = <String>[];
    final parameters = <Object?>[];
    final query = filter.query.trim();
    if (query.isNotEmpty) {
      where.add("(title LIKE ? ESCAPE '!' OR author LIKE ? ESCAPE '!')");
      final pattern = '%${_escapeLike(query)}%';
      parameters
        ..add(pattern)
        ..add(pattern);
    }
    if (filter.status != null) {
      where.add('status = ?');
      parameters.add(filter.status!.name);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final orderSql = switch (filter.sort) {
      BookSort.recentlyAdded => 'added_at DESC',
      BookSort.title => 'title COLLATE NOCASE ASC',
      BookSort.recentlyOpened =>
        'last_opened_at IS NULL ASC, last_opened_at DESC, added_at DESC',
    };
    final rows = database.raw.select(
      'SELECT * FROM books $whereSql ORDER BY $orderSql',
      parameters,
    );
    return rows.map(_bookFromRow).toList();
  }

  Future<Book?> findById(String id) async {
    final rows = database.raw.select('SELECT * FROM books WHERE id = ?', [id]);
    return rows.isEmpty ? null : _bookFromRow(rows.first);
  }

  Future<void> updateStatus(String bookId, BookStatus status) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    database.raw.execute(
      'UPDATE books SET status = ?, updated_at = ? WHERE id = ?',
      [status.name, now, bookId],
    );
  }

  Future<void> markOpened(String bookId) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    database.raw.execute(
      'UPDATE books SET last_opened_at = ?, updated_at = ? WHERE id = ?',
      [now, now, bookId],
    );
  }

  Future<Map<String, String>> getReaderSettings() async {
    final rows = database.raw.select(
      "SELECT key, value FROM settings WHERE key LIKE 'reader.%'",
    );
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> saveReaderSetting(String key, String value) async {
    database.raw.execute(
      '''INSERT OR REPLACE INTO settings (key, value, updated_at)
         VALUES (?, ?, ?)''',
      [key, value, DateTime.now().toUtc().millisecondsSinceEpoch],
    );
  }

  Future<ReadingProgress?> getProgress(String bookId) async {
    final rows = database.raw.select(
      'SELECT book_id, anchor_json, percent, updated_at FROM reading_progress WHERE book_id = ?',
      [bookId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    var page = 1;
    var pageOffset = 0.0;
    final anchor = row['anchor_json'] as String?;
    if (anchor != null && anchor.isNotEmpty) {
      try {
        final decoded = jsonDecode(anchor);
        if (decoded is Map && decoded['page'] is num) {
          page = (decoded['page'] as num).toInt().clamp(1, 1 << 30);
        }
        if (decoded is Map && decoded['offset'] is num) {
          pageOffset = (decoded['offset'] as num)
              .toDouble()
              .clamp(0.0, 1.0)
              .toDouble();
        }
      } catch (_) {
        // An older/corrupt anchor must not block reading from page one.
      }
    }
    return ReadingProgress(
      bookId: row['book_id'] as String,
      pageNumber: page,
      percent: (row['percent'] as num?)?.toDouble() ?? 0,
      pageOffset: pageOffset,
      anchorJson: anchor,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
        isUtc: true,
      ),
    );
  }

  Future<void> saveEpubProgress(
    String bookId, {
    required int chapterIndex,
    required int blockIndex,
    required String cfi,
    required int chapterCount,
  }) async {
    final safeChapter = chapterIndex < 0 ? 0 : chapterIndex;
    final safeBlock = blockIndex < 0 ? 0 : blockIndex;
    final percent = chapterCount <= 0
        ? 0.0
        : ((safeChapter + 1) / chapterCount).clamp(0.0, 1.0).toDouble();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final anchor = jsonEncode({
      'chapter': safeChapter,
      'block': safeBlock,
      'cfi': cfi,
    });
    database.transaction(() {
      database.raw.execute(
        '''UPDATE reading_progress
           SET anchor_json = ?, percent = ?, mode = 'epub', updated_at = ?
           WHERE book_id = ?''',
        [anchor, percent, now, bookId],
      );
      if (database.raw.updatedRows == 0) {
        database.raw.execute(
          '''INSERT INTO reading_progress
             (book_id, anchor_json, percent, mode, updated_at)
             VALUES (?, ?, ?, 'epub', ?)''',
          [bookId, anchor, percent, now],
        );
      }
      database.raw.execute(
        'UPDATE books SET last_opened_at = ?, updated_at = ? WHERE id = ?',
        [now, now, bookId],
      );
    });
  }

  Future<List<Bookmark>> listBookmarks(String bookId) async {
    final rows = database.raw.select(
      'SELECT * FROM bookmarks WHERE book_id = ? ORDER BY created_at DESC',
      [bookId],
    );
    return rows.map(_bookmarkFromRow).toList();
  }

  Future<Bookmark> createBookmark({
    required String bookId,
    int? pageNumber,
    int? chapterIndex,
    int? blockIndex,
    double pageOffset = 0,
    String label = '',
  }) async {
    final existing = database.raw.select(
      '''SELECT * FROM bookmarks
         WHERE book_id = ? AND page_number IS ? AND chapter_index IS ?
           AND block_index IS ? LIMIT 1''',
      [bookId, pageNumber, chapterIndex, blockIndex],
    );
    if (existing.isNotEmpty) return _bookmarkFromRow(existing.first);
    final id = uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    database.raw.execute(
      '''INSERT INTO bookmarks
         (id, book_id, page_number, chapter_index, block_index, page_offset,
          label, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        bookId,
        pageNumber,
        chapterIndex,
        blockIndex,
        pageOffset.clamp(0.0, 1.0).toDouble(),
        label,
        now,
      ],
    );
    final rows = database.raw.select('SELECT * FROM bookmarks WHERE id = ?', [
      id,
    ]);
    return _bookmarkFromRow(rows.first);
  }

  Future<void> deleteBookmark(String id) async {
    database.raw.execute('DELETE FROM bookmarks WHERE id = ?', [id]);
  }

  Bookmark _bookmarkFromRow(Row row) => Bookmark(
    id: row['id'] as String,
    bookId: row['book_id'] as String,
    pageNumber: row['page_number'] as int?,
    chapterIndex: row['chapter_index'] as int?,
    blockIndex: row['block_index'] as int?,
    pageOffset: (row['page_offset'] as num?)?.toDouble() ?? 0,
    label: row['label'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at'] as int,
      isUtc: true,
    ),
  );

  Future<SpeechProgress?> getSpeechProgress(String bookId) async {
    final rows = database.raw.select(
      'SELECT book_id, anchor_json, percent, mode, updated_at '
      'FROM speech_progress WHERE book_id = ?',
      [bookId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SpeechProgress(
      bookId: row['book_id'] as String,
      anchorJson: row['anchor_json'] as String,
      percent: (row['percent'] as num?)?.toDouble() ?? 0,
      mode: row['mode'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
        isUtc: true,
      ),
    );
  }

  Future<void> saveSpeechProgress(
    String bookId, {
    required String anchorJson,
    required double percent,
    required String mode,
  }) async {
    final safePercent = percent.clamp(0.0, 1.0).toDouble();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    database.raw.execute(
      '''INSERT INTO speech_progress
         (book_id, anchor_json, percent, mode, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(book_id) DO UPDATE SET
           anchor_json = excluded.anchor_json,
           percent = excluded.percent,
           mode = excluded.mode,
           updated_at = excluded.updated_at''',
      [bookId, anchorJson, safePercent, mode, now],
    );
  }

  Future<List<RegionAnnotation>> listAnnotations(
    String bookId, {
    String query = '',
  }) async {
    final where = <String>['book_id = ?'];
    final parameters = <Object?>[bookId];
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final pattern = '%${_escapeLike(trimmed)}%';
      where.add("(note LIKE ? ESCAPE '!' OR quote LIKE ? ESCAPE '!')");
      parameters
        ..add(pattern)
        ..add(pattern);
    }
    final rows = database.raw.select(
      'SELECT * FROM annotations WHERE ${where.join(' AND ')} ORDER BY created_at DESC',
      parameters,
    );
    return rows.map(_annotationFromRow).toList();
  }

  Future<List<AnnotationWithBook>> listAllAnnotations({
    String query = '',
  }) async {
    final where = <String>['1 = 1'];
    final parameters = <Object?>[];
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final pattern = '%${_escapeLike(trimmed)}%';
      where.add("(a.note LIKE ? ESCAPE '!' OR a.quote LIKE ? ESCAPE '!')");
      parameters
        ..add(pattern)
        ..add(pattern);
    }
    final rows = database.raw.select('''SELECT a.*,
                COALESCE(NULLIF(a.book_title, ''), b.title, '已删除书籍') AS book_title
         FROM annotations a
         LEFT JOIN books b ON b.id = a.book_id
         WHERE ${where.join(' AND ')}
         ORDER BY a.created_at DESC''', parameters);
    return [
      for (final row in rows)
        AnnotationWithBook(
          annotation: _annotationFromRow(row),
          bookTitle: row['book_title'] as String? ?? '',
        ),
    ];
  }

  Future<RegionAnnotation> createAnnotation({
    required String bookId,
    required double left,
    required double top,
    required double width,
    required double height,
    required String note,
    String quote = '',
    int? pageNumber,
    int? chapterIndex,
    int? blockIndex,
    String color = 'yellow',
    Uint8List? imageBytes,
  }) async {
    final id = uuid.v4();
    final now = DateTime.now().toUtc();
    final bookRows = database.raw.select(
      'SELECT title FROM books WHERE id = ?',
      [bookId],
    );
    if (bookRows.isEmpty) {
      throw StateError('书籍不存在');
    }
    final bookTitle = bookRows.first['title'] as String;
    String? imagePath;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      final directory = Directory(
        p.join(paths.attachmentsDir.path, 'annotations'),
      );
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, '$id.png'));
      await file.writeAsBytes(imageBytes, flush: true);
      imagePath = 'attachments/annotations/$id.png';
    }
    final rect = jsonEncode({
      'left': left.clamp(0.0, 1.0),
      'top': top.clamp(0.0, 1.0),
      'width': width.clamp(0.0, 1.0),
      'height': height.clamp(0.0, 1.0),
    });
    try {
      database.transaction(() {
        database.raw.execute(
          '''INSERT INTO annotations
             (id, book_id, book_title, kind, page_number, chapter_index,
              block_index, rect_json, note, quote, image_path, color,
              created_at, updated_at)
             VALUES (?, ?, ?, 'region', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            id,
            bookId,
            bookTitle,
            pageNumber,
            chapterIndex,
            blockIndex,
            rect,
            note,
            quote,
            imagePath,
            color,
            now.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          ],
        );
      });
    } catch (_) {
      if (imagePath != null) {
        try {
          await paths.resolveRelative(imagePath).delete();
        } catch (_) {}
      }
      rethrow;
    }
    return RegionAnnotation(
      id: id,
      bookId: bookId,
      pageNumber: pageNumber,
      chapterIndex: chapterIndex,
      blockIndex: blockIndex,
      left: left.clamp(0.0, 1.0),
      top: top.clamp(0.0, 1.0),
      width: width.clamp(0.0, 1.0),
      height: height.clamp(0.0, 1.0),
      note: note,
      quote: quote,
      imagePath: imagePath,
      color: color,
      createdAt: now,
    );
  }

  Future<void> deleteAnnotation(String id) async {
    final rows = database.raw.select(
      'SELECT image_path FROM annotations WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return;
    final imagePath = rows.first['image_path'] as String?;
    database.raw.execute('DELETE FROM annotations WHERE id = ?', [id]);
    if (imagePath != null) {
      try {
        await paths.resolveRelative(imagePath).delete();
      } catch (_) {}
    }
  }

  RegionAnnotation _annotationFromRow(Row row) {
    final rect = jsonDecode(row['rect_json'] as String) as Map<String, dynamic>;
    return RegionAnnotation(
      id: row['id'] as String,
      bookId: row['book_id'] as String?,
      pageNumber: row['page_number'] as int?,
      chapterIndex: row['chapter_index'] as int?,
      blockIndex: row['block_index'] as int?,
      left: (rect['left'] as num?)?.toDouble() ?? 0,
      top: (rect['top'] as num?)?.toDouble() ?? 0,
      width: (rect['width'] as num?)?.toDouble() ?? 0,
      height: (rect['height'] as num?)?.toDouble() ?? 0,
      note: row['note'] as String? ?? '',
      quote: row['quote'] as String? ?? '',
      imagePath: row['image_path'] as String?,
      color: row['color'] as String? ?? 'yellow',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
    );
  }

  Future<void> saveProgress(
    String bookId, {
    required int pageNumber,
    required int totalPages,
    double pageOffset = 0,
  }) async {
    final safePage = pageNumber < 1 ? 1 : pageNumber;
    final safeOffset = pageOffset.clamp(0.0, 1.0).toDouble();
    final percent = totalPages <= 0
        ? 0.0
        : (safePage / totalPages).clamp(0.0, 1.0).toDouble();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final anchor = jsonEncode({'page': safePage, 'offset': safeOffset});
    database.transaction(() {
      database.raw.execute(
        '''UPDATE reading_progress
           SET anchor_json = ?, percent = ?, mode = 'pdf', updated_at = ?
           WHERE book_id = ?''',
        [anchor, percent, now, bookId],
      );
      if (database.raw.updatedRows == 0) {
        database.raw.execute(
          '''INSERT INTO reading_progress
             (book_id, anchor_json, percent, mode, updated_at)
             VALUES (?, ?, ?, 'pdf', ?)''',
          [bookId, anchor, percent, now],
        );
      }
      database.raw.execute(
        'UPDATE books SET last_opened_at = ?, updated_at = ? WHERE id = ?',
        [now, now, bookId],
      );
    });
  }

  Future<({int annotations, int bookmarks})> relatedDataCounts(
    String bookId,
  ) async {
    final annotations =
        database.raw.select(
              'SELECT COUNT(*) AS count FROM annotations WHERE book_id = ?',
              [bookId],
            ).first['count']
            as int;
    final bookmarks =
        database.raw.select(
              'SELECT COUNT(*) AS count FROM bookmarks WHERE book_id = ?',
              [bookId],
            ).first['count']
            as int;
    return (annotations: annotations, bookmarks: bookmarks);
  }

  Future<void> deleteBook(String bookId, {bool keepAnnotations = false}) async {
    final rows = database.raw.select(
      'SELECT relative_path, cover_path FROM books WHERE id = ?',
      [bookId],
    );
    if (rows.isEmpty) return;
    final relativePath = rows.first['relative_path'] as String;
    final coverPath = rows.first['cover_path'] as String?;
    final annotationImages = database.raw
        .select(
          'SELECT image_path FROM annotations WHERE book_id = ? AND image_path IS NOT NULL',
          [bookId],
        )
        .map((row) => row['image_path'] as String)
        .toList();
    final quarantined = await files.quarantine(relativePath, bookId);
    try {
      database.transaction(() {
        if (keepAnnotations) {
          database.raw.execute(
            '''UPDATE annotations
               SET book_title = COALESCE(
                     NULLIF(book_title, ''),
                     (SELECT title FROM books WHERE id = ?)
                   ),
                   book_id = NULL
               WHERE book_id = ?''',
            [bookId, bookId],
          );
        }
        database.raw.execute('DELETE FROM books WHERE id = ?', [bookId]);
      });
    } catch (error, stack) {
      try {
        await files.restore(quarantined);
      } catch (_) {
        // Keep the database error. The next startup reconcile can still put a
        // quarantined file back if the restore was blocked.
      }
      Error.throwWithStackTrace(error, stack);
    }
    try {
      await files.purge(quarantined);
    } catch (_) {
      // The database is consistent; a leftover file in cache/trash is safe to
      // clean up later. Never fail a completed delete because trash is locked.
    }
    await _deleteCoverQuietly(coverPath);
    if (keepAnnotations) return;
    for (final imagePath in annotationImages) {
      try {
        await paths.resolveRelative(imagePath).delete();
      } catch (_) {
        // A stale annotation screenshot is safe to leave; metadata is gone.
      }
    }
  }

  /// Best-effort crash recovery for the quarantine window.
  ///
  /// A delete first moves the file to cache/trash and only then removes the
  /// database row. If the app is killed in between, the row still points at a
  /// missing books/ file. On startup, restore that file. Trash files without a
  /// database row are leftovers from a completed delete and can be purged.
  Future<int> reconcileQuarantine() async {
    final rows = database.raw.select('SELECT id, relative_path FROM books');
    final byId = <String, String>{
      for (final row in rows)
        row['id'] as String: row['relative_path'] as String,
    };
    if (!await paths.trashDir.exists()) return 0;
    var restored = 0;
    await for (final entity in paths.trashDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final id = p.basenameWithoutExtension(entity.path);
      final relativePath = byId[id];
      try {
        if (relativePath == null) {
          await entity.delete();
          continue;
        }
        final target = paths.resolveRelative(relativePath);
        if (await target.exists()) {
          await entity.delete();
          continue;
        }
        await entity.rename(target.path);
        restored++;
      } catch (_) {
        // Leave the trash entry for the next startup instead of losing it.
      }
    }
    return restored;
  }

  Future<void> _deleteStoredQuietly(StoredBookFile stored) async {
    try {
      await files.deleteRelative(stored.relativePath);
    } catch (_) {
      // A failed cleanup must not turn a duplicate/import outcome into a crash.
    }
  }

  Future<void> _deleteCoverQuietly(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    try {
      await files.deleteRelative(relativePath);
    } catch (_) {
      // Covers are regenerable; never fail the book operation for one.
    }
  }

  /// Generates covers for books imported before cover extraction existed.
  ///
  /// Runs one book at a time on the UI isolate after the library has rendered;
  /// malformed books simply keep their generated fallback cover.
  Future<int> backfillMissingCovers() async {
    final rows = database.raw.select(
      "SELECT id, relative_path, format FROM books WHERE cover_path IS NULL AND format IN ('pdf', 'epub', 'docx')",
    );
    var created = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final relativePath = row['relative_path'] as String;
      try {
        final source = paths.resolveRelative(relativePath);
        if (!await source.exists()) continue;
        final format = BookFormat.fromStorage(row['format'] as String);
        final coverPath = await coverExtractor.extract(
          file: source,
          format: format,
          bookId: id,
          paths: paths,
        );
        if (coverPath == null) continue;
        database.raw.execute(
          'UPDATE books SET cover_path = ?, updated_at = ? WHERE id = ?',
          [coverPath, DateTime.now().toUtc().millisecondsSinceEpoch, id],
        );
        created++;
      } catch (_) {
        // Leave cover_path null; the next launch can retry this book.
      }
    }
    return created;
  }

  Future<StorageStats> storageStats() async {
    final count =
        database.raw.select('SELECT COUNT(*) AS n FROM books').first['n']
            as int;
    final bytes =
        database.raw
                .select('SELECT COALESCE(SUM(file_size), 0) AS n FROM books')
                .first['n']
            as int;
    return StorageStats(
      bookCount: count,
      totalBookBytes: bytes,
      databaseVersion: database.schemaVersion,
      dataRoot: paths.root.path,
    );
  }

  Book _bookFromRow(Row row) {
    return Book(
      id: row['id'] as String,
      title: row['title'] as String,
      author: row['author'] as String? ?? '',
      format: BookFormat.fromStorage(row['format'] as String),
      originalFileName: row['original_file_name'] as String,
      relativePath: row['relative_path'] as String,
      fileHash: row['file_hash'] as String,
      fileSize: row['file_size'] as int,
      coverPath: row['cover_path'] as String?,
      status: BookStatus.fromStorage(row['status'] as String),
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        row['added_at'] as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
        isUtc: true,
      ),
      lastOpenedAt: row['last_opened_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['last_opened_at'] as int,
              isUtc: true,
            ),
      metadataSource: row['metadata_source'] as String? ?? 'file_name',
    );
  }

  String _escapeLike(String input) =>
      input.replaceAll('!', '!!').replaceAll('%', '!%').replaceAll('_', '!_');
}
