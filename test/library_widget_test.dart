import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moye/app/moye_app.dart';
import 'package:moye/app/providers.dart';
import 'package:moye/core/app_services.dart';
import 'package:moye/core/database/library_database.dart';
import 'package:moye/core/storage/app_paths.dart';
import 'package:moye/core/storage/book_file_store.dart';
import 'package:moye/features/library/data/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppServices services;
  late LibraryRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moye_widget_test_');
    final paths = await AppPaths.forRoot(temp);
    final database = LibraryDatabase.open(paths.databaseFile);
    repository = LibraryRepository(
      database: database,
      paths: paths,
      files: BookFileStore(paths),
    );
    services = AppServices(
      paths: paths,
      database: database,
      library: repository,
    );
  });

  tearDown(() async {
    services.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  testWidgets('empty library renders and settings routes are reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-empty')), findsOneWidget);
    expect(find.byKey(const Key('import-books-button')), findsOneWidget);
    expect(find.text('书库还是空的'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-storage-card')), findsOneWidget);
    expect(find.byKey(const Key('settings-backup-card')), findsOneWidget);
    expect(find.byKey(const Key('export-backup-button')), findsOneWidget);
    expect(find.byKey(const Key('restore-backup-button')), findsOneWidget);
    expect(find.text('应用数据'), findsOneWidget);

    await tester.tap(find.text('标记'));
    await tester.pumpAndSettle();
    expect(find.text('知识仓库'), findsOneWidget);
    expect(find.byKey(const Key('all-annotations-search')), findsOneWidget);
  });

  testWidgets('mobile layout fits the empty library and import control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-empty')), findsOneWidget);
    expect(find.byKey(const Key('import-books-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('imported books render, persist selection details and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imported = await tester.runAsync(
      () => repository.importFile(p.join('test', 'fixtures', 'sample.pdf')),
    );
    final book = imported!.book!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-book-count')), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    final card = find.byKey(Key('book-card-${book.id}'));
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-details')), findsOneWidget);
    expect(find.text(book.title), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('library-search')),
      'not-a-title',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('library-no-results')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('library-search')), '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byKey(const Key('library-view-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-list')), findsOneWidget);

    final visibleCard = find.byKey(Key('book-card-${book.id}'));
    await tester.tap(visibleCard);
    await tester.pumpAndSettle();
    final detailsScrollable = find
        .descendant(
          of: find.byKey(const Key('book-details')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('从书库删除'),
      260,
      scrollable: detailsScrollable,
      maxScrolls: 20,
    );
    // The reader button adds height; make sure the destructive action is not
    // sitting half outside the viewport before tapping it.
    await tester.drag(detailsScrollable, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从书库删除'));
    await tester.pumpAndSettle();
    expect(find.text('从书库删除？'), findsOneWidget);
    // Widget tests use FakeAsync; real file I/O happens through runAsync in
    // the dedicated repository tests. Here we verify the destructive action is
    // gated by an explicit confirmation dialog.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text(book.title), findsWidgets);
    await tester.runAsync(() => repository.deleteBook(book.id));
    expect(await tester.runAsync(() => repository.listBooks()), isEmpty);
  });

  testWidgets('duplicate import is reported without adding a second card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = await tester.runAsync(
      () => repository.importFile(p.join('test', 'fixtures', 'sample.epub')),
    );
    final duplicate = await tester.runAsync(
      () => repository.importFile(p.join('test', 'fixtures', 'sample.epub')),
    );
    expect(first!.kind, ImportOutcomeKind.imported);
    expect(duplicate!.kind, ImportOutcomeKind.duplicate);
    expect(await repository.listBooks(), hasLength(1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 本'), findsOneWidget);
    expect(find.text('墨页 EPUB3 验证样本'), findsWidgets);
  });
}
