import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moye/core/database/library_database.dart';
import 'package:moye/core/database/migrations.dart';
import 'package:moye/core/epub/epub_parser.dart';
import 'package:moye/core/models/book.dart';
import 'package:moye/core/storage/app_paths.dart';
import 'package:moye/core/storage/book_file_store.dart';
import 'package:moye/features/library/data/library_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temp;
  late AppPaths paths;
  LibraryDatabase? database;
  late LibraryRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moye_phase1_test_');
    paths = await AppPaths.forRoot(temp);
    database = LibraryDatabase.open(paths.databaseFile);
    repository = _repository(paths, database!);
  });

  tearDown(() async {
    database?.close();
    database = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('schema v5 creates the library tables and enables foreign keys', () {
    expect(database!.schemaVersion, 5);
    final tables = database!.raw
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      tables,
      containsAll([
        'books',
        'shelves',
        'book_shelves',
        'tags',
        'book_tags',
        'reading_progress',
        'settings',
        'annotations',
        'speech_progress',
        'bookmarks',
      ]),
    );
    expect(database!.raw.select('PRAGMA foreign_keys').first.columnAt(0), 1);
    expect(
      (database!.raw.select('PRAGMA journal_mode').first.columnAt(0) as String)
          .toLowerCase(),
      'wal',
    );
  });

  test(
    'imports a real PDF, copies it into private storage and creates progress',
    () async {
      final outcome = await repository.importFile(_fixture('sample.pdf'));
      expect(outcome.kind, ImportOutcomeKind.imported);
      final book = outcome.book!;
      expect(book.format, BookFormat.pdf);
      expect(book.title, 'sample');
      expect(book.fileHash, hasLength(64));
      expect(book.status, BookStatus.notStarted);
      expect(book.relativePath, startsWith('books/'));
      expect(await paths.resolveRelative(book.relativePath).exists(), isTrue);
      expect(
        database!.raw
            .select('SELECT COUNT(*) AS n FROM reading_progress')
            .first['n'],
        1,
      );
    },
  );

  test(
    'extracts EPUB and DOCX metadata instead of relying on the file name',
    () async {
      final epub = await repository.importFile(_fixture('sample.epub'));
      final docx = await repository.importFile(_fixture('sample.docx'));
      expect(epub.kind, ImportOutcomeKind.imported);
      expect(epub.book!.title, '墨页 EPUB3 验证样本');
      expect(epub.book!.author, 'MOYE Phase 0');
      expect(epub.book!.metadataSource, 'epub_opf');
      expect(docx.kind, ImportOutcomeKind.imported);
      expect(docx.book!.title, '墨页 DOCX 验证样本');
      expect(docx.book!.author, 'MOYE Phase 0');
      expect(docx.book!.metadataSource, 'docx_core');
    },
  );

  test('extracts real covers for PDF, EPUB and DOCX', () async {
    final pdf = await repository.importFile(_fixture('sample.pdf'));
    final epub = await repository.importFile(_fixture('sample.epub'));
    final docx = await repository.importFile(_fixture('sample.docx'));

    expect(pdf.book!.coverPath, isNotNull);
    expect(epub.book!.coverPath, isNotNull);
    expect(docx.book!.coverPath, isNotNull);
    for (final book in [pdf.book!, epub.book!, docx.book!]) {
      final cover = paths.resolveRelative(book.coverPath!);
      expect(await cover.exists(), isTrue, reason: book.format.name);
      expect(await cover.length(), greaterThan(500), reason: book.format.name);
    }
  });

  test('rejects duplicate content and removes the duplicate copy', () async {
    final first = await repository.importFile(_fixture('sample.pdf'));
    final second = await repository.importFile(_fixture('sample.pdf'));
    expect(first.kind, ImportOutcomeKind.imported);
    expect(second.kind, ImportOutcomeKind.duplicate);
    final books = await repository.listBooks();
    expect(books, hasLength(1));
    final files = Directory(paths.booksDir.path)
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.contains('.part'))
        .toList();
    expect(files, hasLength(1));
  });

  test('rejects unsupported extensions without writing a book file', () async {
    final unsupported = File(p.join(temp.path, 'notes.xyz'));
    await unsupported.writeAsString('not a book');
    final outcome = await repository.importFile(unsupported.path);
    expect(outcome.kind, ImportOutcomeKind.unsupported);
    expect(await repository.listBooks(), isEmpty);
    expect(
      Directory(paths.booksDir.path).listSync().whereType<File>(),
      isEmpty,
    );
  });

  test('persists EPUB reader settings', () async {
    await repository.saveReaderSetting('reader.epub.fontSize', '22.0');
    await repository.saveReaderSetting('reader.epub.lineHeight', '2.0');
    await repository.saveReaderSetting('reader.epub.paragraphSpacing', '16.0');
    final settings = await repository.getReaderSettings();
    expect(settings['reader.epub.fontSize'], '22.0');
    expect(settings['reader.epub.lineHeight'], '2.0');
    expect(settings['reader.epub.paragraphSpacing'], '16.0');
  });

  test('creates, deduplicates, lists and deletes bookmarks', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    final book = imported.book!;
    final first = await repository.createBookmark(
      bookId: book.id,
      pageNumber: 4,
      pageOffset: 0.25,
      label: '重点页',
    );
    final duplicate = await repository.createBookmark(
      bookId: book.id,
      pageNumber: 4,
      pageOffset: 0.8,
    );
    expect(duplicate.id, first.id);
    final bookmarks = await repository.listBookmarks(book.id);
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.locationLabel, '第 4 页');
    expect(bookmarks.single.pageOffset, closeTo(0.25, 0.001));

    await repository.deleteBookmark(first.id);
    expect(await repository.listBookmarks(book.id), isEmpty);
  });

  test('persists independent speech progress', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    final book = imported.book!;
    await repository.saveSpeechProgress(
      book.id,
      anchorJson: '{"page":2,"offset":0.4}',
      percent: 0.65,
      mode: 'pdf',
    );
    final progress = await repository.getSpeechProgress(book.id);
    expect(progress, isNotNull);
    expect(progress!.anchorJson, '{"page":2,"offset":0.4}');
    expect(progress.anchor['page'], 2);
    expect(progress.percent, 0.65);
    expect(progress.mode, 'pdf');
  });

  test('extracts EPUB internal link ranges and anchors', () async {
    final document = const EpubParser().parse(
      await File(_fixture('sample_links.epub')).readAsBytes(),
    );
    final chapter = document.chapters.first;
    final linked = chapter.blocks.firstWhere((block) => block.links.isNotEmpty);
    final link = linked.links.first;
    expect(linked.text.substring(link.start, link.end), '查看脚注');
    expect(link.target, contains('chapter1.xhtml#note-1'));
    expect(chapter.anchors['note-1'], isNotNull);
    expect(chapter.blocks[chapter.anchors['note-1']!].text, contains('这是脚注内容'));
    final table = chapter.blocks.firstWhere(
      (block) => block.kind == EpubBlockKind.table,
    );
    expect(
      table.tableRows
          .map((row) => row.map((cell) => cell.text).toList())
          .toList(),
      [
        ['项目', '状态'],
        ['表格渲染', '通过'],
      ],
    );
    expect(table.tableHeaderRows, 1);
    final rubyBlock = chapter.blocks.firstWhere(
      (block) => block.rubies.isNotEmpty,
    );
    final ruby = rubyBlock.rubies.first;
    expect(rubyBlock.text.substring(ruby.start, ruby.end), '漢字');
    expect(ruby.annotation, 'かんじ');
    expect(rubyBlock.text, '漢字 的注音。');
  });

  test('parses merged cells and ignores nested table rows', () {
    final document = const EpubParser().parse(_mergedTableEpub());
    final table = document.chapters.first.blocks.firstWhere(
      (block) => block.kind == EpubBlockKind.table,
    );
    expect(table.tableRows.length, 2);
    expect(table.tableRows[0][0].text, '项目');
    expect(table.tableRows[0][0].rowSpan, 2);
    expect(table.tableRows[0][1].text, '结果');
    expect(table.tableRows[0][1].colSpan, 2);
    expect(table.tableRows[1][0].text, '合并单元格');
    expect(table.tableRows[1][1].text, contains('嵌套内容'));
    expect(table.tableHeaderRows, 1);
    expect(table.text, contains('嵌套内容'));
  });

  test('parses EPUB chapters and saves an EPUB anchor', () async {
    final document = const EpubParser().parse(
      await File(_fixture('sample.epub')).readAsBytes(),
    );
    expect(document.title, '墨页 EPUB3 验证样本');
    expect(document.chapters, isNotEmpty);
    expect(document.toc, isNotEmpty);
    expect(document.chapters.first.blocks, isNotEmpty);

    final imported = await repository.importFile(_fixture('sample.epub'));
    final book = imported.book!;
    await repository.saveEpubProgress(
      book.id,
      chapterIndex: 0,
      blockIndex: 1,
      cfi: document.cfiFor(document.chapters.first, 1),
      chapterCount: document.chapters.length,
    );
    final progress = await repository.getProgress(book.id);
    expect(progress!.anchorJson, contains('"chapter":0'));
    expect(progress.anchorJson, contains('"block":1'));
  });

  test('creates, searches and deletes a region annotation', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    final book = imported.book!;
    final annotation = await repository.createAnnotation(
      bookId: book.id,
      left: 0.1,
      top: 0.2,
      width: 0.3,
      height: 0.25,
      note: '这一段是重点',
      quote: '原文引用',
      pageNumber: 3,
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    expect(annotation.imagePath, isNotNull);
    expect(await paths.resolveRelative(annotation.imagePath!).exists(), isTrue);

    final all = await repository.listAnnotations(book.id);
    expect(all, hasLength(1));
    expect(all.single.note, '这一段是重点');
    expect(all.single.pageNumber, 3);

    final found = await repository.listAnnotations(book.id, query: '重点');
    expect(found, hasLength(1));
    final global = await repository.listAllAnnotations(query: '重点');
    expect(global, hasLength(1));
    expect(global.single.bookTitle, isNotEmpty);
    expect(global.single.annotation.id, annotation.id);
    final missing = await repository.listAnnotations(book.id, query: '不存在');
    expect(missing, isEmpty);

    await repository.deleteAnnotation(annotation.id);
    expect(await repository.listAnnotations(book.id), isEmpty);
    expect(
      await paths.resolveRelative(annotation.imagePath!).exists(),
      isFalse,
    );
  });

  test('migrates schema v4 annotations without losing data', () {
    final legacyPath = p.join(temp.path, 'legacy_v4.db');
    final raw = sqlite3.open(legacyPath);
    try {
      for (var version = 1; version <= 4; version++) {
        for (final sql in libraryMigrations[version]!) {
          raw.execute(sql);
        }
      }
      raw.execute('''INSERT INTO books
           (id, title, author, format, original_file_name, relative_path,
            file_hash, file_size, cover_path, status, added_at, updated_at,
            last_opened_at, metadata_source)
           VALUES ('legacy-book', '旧书', '', 'pdf', 'legacy.pdf',
                   'books/legacy.pdf', 'legacy-hash', 1, NULL, 'notStarted',
                   0, 0, NULL, 'file_name')''');
      raw.execute('''INSERT INTO annotations
           (id, book_id, kind, page_number, chapter_index, block_index,
            rect_json, note, quote, image_path, color, created_at, updated_at)
           VALUES ('legacy-annotation', 'legacy-book', 'region', 1,
                   NULL, NULL, '{}', '旧标记', '', NULL, 'yellow', 0, 0)''');
      raw.execute('PRAGMA user_version = 4');
    } finally {
      raw.close();
    }

    final migrated = LibraryDatabase.open(File(legacyPath));
    try {
      expect(migrated.schemaVersion, 5);
      final row = migrated.raw
          .select('SELECT book_id, book_title, note FROM annotations')
          .first;
      expect(row['book_id'], 'legacy-book');
      expect(row['book_title'], '旧书');
      expect(row['note'], '旧标记');
    } finally {
      migrated.close();
    }
  });

  test('keeps annotations when deleting a book with keepAnnotations', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    final book = imported.book!;
    final annotation = await repository.createAnnotation(
      bookId: book.id,
      left: 0.1,
      top: 0.2,
      width: 0.3,
      height: 0.4,
      note: '保留这条标记',
      pageNumber: 1,
      imageBytes: Uint8List.fromList([7, 8, 9]),
    );
    final image = paths.resolveRelative(annotation.imagePath!);

    await repository.deleteBook(book.id, keepAnnotations: true);
    expect(await repository.listBooks(), isEmpty);
    expect(await image.exists(), isTrue);

    final all = await repository.listAllAnnotations();
    expect(all, hasLength(1));
    expect(all.single.annotation.bookId, isNull);
    expect(all.single.bookTitle, book.title);
    expect(all.single.annotation.note, '保留这条标记');
  });

  test('updates recent reading time without auto-changing status', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    final book = imported.book!;
    expect(book.lastOpenedAt, isNull);
    await repository.markOpened(book.id);
    final refreshed = await repository.findById(book.id);
    expect(refreshed!.lastOpenedAt, isNotNull);
    expect(refreshed.status, BookStatus.notStarted);
    expect(
      refreshed.lastOpenedAt!.isAfter(
        book.addedAt.subtract(const Duration(seconds: 1)),
      ),
      isTrue,
    );
  });

  test('saves and restores PDF page position and page offset', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    final book = imported.book!;
    await repository.saveProgress(
      book.id,
      pageNumber: 2,
      totalPages: 4,
      pageOffset: 0.35,
    );

    final progress = await repository.getProgress(book.id);
    expect(progress, isNotNull);
    expect(progress!.pageNumber, 2);
    expect(progress.pageOffset, closeTo(0.35, 0.001));
    expect(progress.percent, closeTo(0.5, 0.001));
    expect(progress.anchorJson, contains('"offset":0.35'));

    database!.close();
    database = LibraryDatabase.open(paths.databaseFile);
    repository = _repository(paths, database!);
    final restored = await repository.getProgress(book.id);
    expect(restored!.pageNumber, 2);
    expect(restored.pageOffset, closeTo(0.35, 0.001));
  });

  test(
    'repairs a duplicate record when its original file is missing',
    () async {
      final first = await repository.importFile(_fixture('sample.pdf'));
      final firstPath = paths.resolveRelative(first.book!.relativePath);
      await firstPath.delete();

      final repaired = await repository.importFile(_fixture('sample.pdf'));
      expect(repaired.kind, ImportOutcomeKind.imported);
      expect(repaired.book!.id, first.book!.id);
      expect(repaired.book!.relativePath, isNot(first.book!.relativePath));
      expect(
        await paths.resolveRelative(repaired.book!.relativePath).exists(),
        isTrue,
      );
      expect(await repository.listBooks(), hasLength(1));
    },
  );

  test('restores a quarantined file after a simulated delete crash', () async {
    final imported = await repository.importFile(_fixture('sample.epub'));
    final book = imported.book!;
    final original = paths.resolveRelative(book.relativePath);
    await repository.files.quarantine(book.relativePath, book.id);
    expect(await original.exists(), isFalse);

    expect(await repository.reconcileQuarantine(), 1);
    expect(await original.exists(), isTrue);
    expect(await repository.findById(book.id), isNotNull);
  });

  test('rejects a database created by a newer application version', () async {
    database!.raw.execute('PRAGMA user_version = 6');
    database!.close();
    database = null;
    expect(
      () => LibraryDatabase.open(paths.databaseFile),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects an unsupported stream before creating a cache file', () async {
    final outcome = await repository.importStream(
      sourceName: 'video.mp4',
      source: Stream<List<int>>.value([1, 2, 3]),
    );
    expect(outcome.kind, ImportOutcomeKind.unsupported);
    expect(
      Directory(paths.cacheDir.path).listSync().whereType<File>(),
      isEmpty,
    );
  });

  test('cleans cache when the picked stream fails mid-import', () async {
    final outcome = await repository.importStream(
      sourceName: 'broken.pdf',
      source: Stream<List<int>>.error(const FileSystemException('read failed')),
    );
    expect(outcome.kind, ImportOutcomeKind.failed);
    expect(
      Directory(paths.cacheDir.path).listSync().whereType<File>(),
      isEmpty,
    );
    expect(await repository.listBooks(), isEmpty);
  });

  test('persists books across database close and reopen', () async {
    final imported = await repository.importFile(_fixture('sample.epub'));
    final id = imported.book!.id;
    database!.close();
    database = LibraryDatabase.open(paths.databaseFile);
    repository = _repository(paths, database!);
    final restored = await repository.findById(id);
    expect(restored, isNotNull);
    expect(restored!.title, '墨页 EPUB3 验证样本');
    expect(restored.fileHash, imported.book!.fileHash);
  });

  test('filters by status and escaped title search', () async {
    final imported = await repository.importFile(_fixture('sample.pdf'));
    await repository.updateStatus(imported.book!.id, BookStatus.reading);
    final reading = await repository.listBooks(
      const LibraryFilter(status: BookStatus.reading),
    );
    expect(reading, hasLength(1));
    final notStarted = await repository.listBooks(
      const LibraryFilter(status: BookStatus.notStarted),
    );
    expect(notStarted, isEmpty);
    final search = await repository.listBooks(
      const LibraryFilter(query: 'sample'),
    );
    expect(search, hasLength(1));
    final noMatch = await repository.listBooks(
      const LibraryFilter(query: 'missing'),
    );
    expect(noMatch, isEmpty);
  });

  test('escapes LIKE wildcards and exclamation marks', () async {
    await repository.importFile(_fixture('sample.pdf'));
    final special = File(p.join(temp.path, '100%_reading.txt'));
    await special.writeAsString('literal wildcard title');
    await repository.importFile(special.path);

    final percent = await repository.listBooks(const LibraryFilter(query: '%'));
    expect(percent.map((book) => book.title), ['100%_reading']);
    final underscore = await repository.listBooks(
      const LibraryFilter(query: '_'),
    );
    expect(underscore.map((book) => book.title), ['100%_reading']);
    final escaped = await repository.listBooks(
      const LibraryFilter(query: '%_'),
    );
    expect(escaped.map((book) => book.title), ['100%_reading']);
  });

  test('deletes the book row, progress and private file', () async {
    final imported = await repository.importFile(_fixture('sample.docx'));
    final book = imported.book!;
    final file = paths.resolveRelative(book.relativePath);
    expect(await file.exists(), isTrue);
    await repository.deleteBook(book.id);
    expect(await repository.listBooks(), isEmpty);
    expect(await file.exists(), isFalse);
    expect(
      database!.raw
          .select('SELECT COUNT(*) AS n FROM reading_progress')
          .first['n'],
      0,
    );
  });

  test('rejects path traversal in relative database paths', () {
    expect(() => paths.resolveRelative('../outside.txt'), throwsArgumentError);
    expect(() => paths.resolveRelative('/absolute.txt'), throwsArgumentError);
  });
}

LibraryRepository _repository(AppPaths paths, LibraryDatabase database) {
  return LibraryRepository(
    database: database,
    paths: paths,
    files: BookFileStore(paths),
  );
}

String _fixture(String name) => p.join('test', 'fixtures', name);

Uint8List _mergedTableEpub() {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile.bytes(name, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
  add('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:uuid:moye-merged-table</dc:identifier>
    <dc:title>合并表格测试</dc:title>
    <dc:language>zh-CN</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>''');
  add('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol>
<li><a href="text/chapter1.xhtml">第一章</a></li>
</ol></nav></body></html>''');
  add('OEBPS/text/chapter1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>合并表格</h1>
<table id="merged-table">
  <thead>
    <tr><th rowspan="2">项目</th><th colspan="2">结果</th></tr>
  </thead>
  <tbody>
    <tr>
      <td>合并单元格</td>
      <td><table><tr><td>嵌套内容</td></tr></table></td>
    </tr>
  </tbody>
</table>
</body></html>''');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
