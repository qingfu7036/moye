import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moye/core/backup/backup_service.dart';
import 'package:moye/core/database/library_database.dart';
import 'package:moye/core/storage/app_paths.dart';
import 'package:moye/core/storage/book_file_store.dart';
import 'package:moye/features/library/data/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;
  late LibraryDatabase database;
  late LibraryRepository repository;
  late String bookId;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moye_backup_test_');
    paths = await AppPaths.forRoot(temp);
    database = LibraryDatabase.open(paths.databaseFile);
    repository = LibraryRepository(
      database: database,
      paths: paths,
      files: BookFileStore(paths),
    );
    final imported = await repository.importFile(
      p.join('test', 'fixtures', 'sample.pdf'),
    );
    expect(imported.book, isNotNull);
    bookId = imported.book!.id;
    await repository.createAnnotation(
      bookId: bookId,
      left: 0.1,
      top: 0.2,
      width: 0.3,
      height: 0.4,
      note: 'backup attachment',
      pageNumber: 1,
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
    );
  });

  tearDown(() async {
    database.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('exports a .moye package and restores it after restart', () async {
    final service = BackupService(paths: paths, database: database);
    final exportFile = File(p.join(temp.path, 'exports', 'library.moye'));
    final result = await service.exportTo(exportFile);

    expect(await exportFile.exists(), isTrue);
    expect(result.fileCount, greaterThanOrEqualTo(2));
    expect(result.totalBytes, greaterThan(0));
    expect(await exportFile.length(), greaterThan(0));

    // Add a second book, then restore the one-book snapshot.
    await repository.importFile(p.join('test', 'fixtures', 'sample.epub'));
    expect((await repository.listBooks()).length, 2);

    database.close();
    final preview = await service.prepareRestore(exportFile);
    expect(preview.manifest.bookCount, 1);
    expect(BackupService.hasPendingRestore(paths), isTrue);

    final applied = await BackupService.applyPendingRestore(paths);
    expect(applied, isNotNull);
    expect(BackupService.hasPendingRestore(paths), isFalse);
    expect(await applied!.safetyDirectory.exists(), isTrue);

    database = LibraryDatabase.open(paths.databaseFile);
    repository = LibraryRepository(
      database: database,
      paths: paths,
      files: BookFileStore(paths),
    );
    final books = await repository.listBooks();
    expect(books.length, 1);
    expect(books.single.title, isNotEmpty);
    expect(
      await paths.resolveRelative(books.single.relativePath).exists(),
      isTrue,
    );
    final annotations = await repository.listAnnotations(bookId);
    expect(annotations.length, 1);
    expect(annotations.single.note, 'backup attachment');
    expect(
      await paths.resolveRelative(annotations.single.imagePath!).exists(),
      isTrue,
    );
  });

  test('rolls back a restore interrupted during the directory swap', () async {
    final service = BackupService(paths: paths, database: database);
    final exportFile = File(p.join(temp.path, 'interrupted.moye'));
    await service.exportTo(exportFile);
    database.close();
    await service.prepareRestore(exportFile);

    final safety = Directory(
      p.join(paths.backupsDir.path, 'pre-restore-crash-test'),
    );
    await safety.create(recursive: true);
    await paths.databaseDir.rename(p.join(safety.path, 'database'));
    final marker = File(
      p.join(paths.backupsDir.path, 'restore-in-progress.json'),
    );
    await marker.writeAsString(
      jsonEncode({'safety': 'pre-restore-crash-test'}),
      flush: true,
    );

    final recovered = await BackupService.recoverInterruptedRestore(paths);
    expect(recovered, isNotNull);
    expect(await marker.exists(), isFalse);
    expect(await paths.databaseFile.exists(), isTrue);

    database = LibraryDatabase.open(paths.databaseFile);
    repository = LibraryRepository(
      database: database,
      paths: paths,
      files: BookFileStore(paths),
    );
    expect((await repository.listBooks()).length, 1);
  });

  test(
    'rejects a corrupted backup without touching the active library',
    () async {
      final service = BackupService(paths: paths, database: database);
      final exportFile = File(p.join(temp.path, 'broken.moye'));
      await service.exportTo(exportFile);

      final bytes = await exportFile.readAsBytes();
      await exportFile.writeAsBytes(bytes.sublist(0, bytes.length - 80));

      await expectLater(
        service.prepareRestore(exportFile),
        throwsA(isA<BackupException>()),
      );
      expect(BackupService.hasPendingRestore(paths), isFalse);
      expect((await repository.listBooks()).length, 1);
    },
  );
}
