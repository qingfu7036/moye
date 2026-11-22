import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moye/app/moye_app.dart';
import 'package:moye/app/providers.dart';
import 'package:moye/core/app_services.dart';
import 'package:moye/core/database/library_database.dart';
import 'package:moye/core/storage/app_paths.dart';
import 'package:moye/core/storage/book_file_store.dart';
import 'package:moye/features/library/data/library_repository.dart';
import 'package:moye/features/reader/presentation/widgets/region_mark_layer.dart';
import 'package:path/path.dart' as p;

AppServices _services(AppPaths paths) {
  final database = LibraryDatabase.open(paths.databaseFile);
  return AppServices(
    paths: paths,
    database: database,
    library: LibraryRepository(
      database: database,
      paths: paths,
      files: BookFileStore(paths),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'Timed out waiting for ${finder.describeMatch(Plurality.many)}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates a region note and finds it in the book warehouse', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('moye_annotation_test_'),
    );
    final paths = (await tester.runAsync(() => AppPaths.forRoot(temp!)))!;
    final services = _services(paths);
    addTearDown(() async {
      try {
        services.dispose();
      } catch (_) {}
      if (await temp!.exists()) await temp.delete(recursive: true);
    });

    final imported = await tester.runAsync(
      () => services.library.importFile(
        p.join('test', 'fixtures', 'sample.epub'),
      ),
    );
    final book = imported!.book!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('book-card-${book.id}')));
    await tester.pumpAndSettle();

    final detailsScrollable = find
        .descendant(
          of: find.byKey(const Key('book-details')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(detailsScrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-reader-button')));
    await _pumpUntil(tester, find.byKey(const Key('epub-chapter-indicator')));

    await tester.tap(find.byTooltip('标记区域'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(RegionMarkLayer), const Offset(160, 110));
    await _pumpUntil(tester, find.text('给这个标记写备注'));
    await tester.enterText(find.byType(TextField).last, '这段需要以后回看');
    await tester.tap(find.text('保存标记'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => services.library.listAnnotations(book.id),
    );
    expect(saved, hasLength(1));
    // EPUB is a Flutter surface, so the rectangular crop must be captured.
    expect(saved!.single.imagePath, isNotNull);
    expect(
      find.byKey(Key('annotation-marker-${saved.single.id}')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('返回书库'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('book-card-${book.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-details')), findsOneWidget);
    // The details list remembers its scroll offset; go back to the top where
    // the annotation entry point sits after the reader button.
    await tester.drag(detailsScrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-annotations-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-annotations-button')));
    await tester.pumpAndSettle();
    expect(find.text('本书仓库'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('annotation-search')), '回看');
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('这段需要以后回看'), findsOneWidget);
  });

  _pdfAnnotationTest();
}

void _pdfAnnotationTest() {
  testWidgets('captures a PDF region annotation screenshot', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('moye_pdf_annotation_'),
    );
    final paths = (await tester.runAsync(() => AppPaths.forRoot(temp!)))!;
    final services = _services(paths);
    addTearDown(() async {
      try {
        services.dispose();
      } catch (_) {}
      if (await temp!.exists()) await temp.delete(recursive: true);
    });
    final imported = await tester.runAsync(
      () =>
          services.library.importFile(p.join('test', 'fixtures', 'sample.pdf')),
    );
    final book = imported!.book!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('book-card-${book.id}')));
    await tester.pumpAndSettle();
    final detailsScrollable = find
        .descendant(
          of: find.byKey(const Key('book-details')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(detailsScrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-reader-button')));
    await _pumpUntil(tester, find.byKey(const Key('reader-page-indicator')));
    await tester.tap(find.byTooltip('标记区域'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(RegionMarkLayer), const Offset(160, 110));
    await _pumpUntil(tester, find.text('给这个标记写备注'));
    await tester.enterText(find.byType(TextField).last, 'PDF 区域备注');
    await tester.tap(find.text('保存标记'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => services.library.listAnnotations(book.id),
    );
    expect(saved, hasLength(1));
    expect(saved!.single.imagePath, isNotNull);
    expect(
      find.byKey(Key('annotation-marker-${saved.single.id}')),
      findsOneWidget,
    );
  });
}
