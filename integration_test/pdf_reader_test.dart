import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:moye/app/moye_app.dart';
import 'package:moye/app/providers.dart';
import 'package:moye/core/app_services.dart';
import 'package:moye/core/database/library_database.dart';
import 'package:moye/core/models/book.dart';
import 'package:moye/core/storage/app_paths.dart';
import 'package:moye/core/storage/book_file_store.dart';
import 'package:moye/features/library/data/library_repository.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

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
  pdfrxFlutterInitialize();

  testWidgets('opens a PDF at its saved page and returns to the library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('moye_reader_test_'),
    );
    final paths = (await tester.runAsync(() => AppPaths.forRoot(temp!)))!;
    final services = _services(paths);
    addTearDown(() async {
      try {
        services.dispose();
      } catch (_) {}
      if (await temp!.exists()) await temp.delete(recursive: true);
    });

    final fixture = p.join('test', 'fixtures', 'sample_outline.pdf');
    final imported = await tester.runAsync(
      () => services.library.importFile(fixture),
    );
    final book = imported!.book!;

    await tester.runAsync(() async {
      Pdfrx.cacheDirectoryPath ??= paths.cacheDir.path;
      final document = await PdfDocument.openFile(fixture);
      final pages = document.pages.length;
      await document.dispose();
      await services.library.saveProgress(
        book.id,
        pageNumber: pages >= 2 ? 2 : 1,
        totalPages: pages,
        pageOffset: 0.35,
      );
      await services.library.saveReaderSetting('reader.pdf.zoom', '1.5');
    });

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
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-reader-button')),
      220,
      scrollable: detailsScrollable,
      maxScrolls: 20,
    );
    await tester.tap(find.byKey(const Key('open-reader-button')));
    await _pumpUntil(tester, find.byKey(const Key('reader-page-indicator')));

    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.textContaining('2 /'), findsOneWidget);
    expect(find.byTooltip('选择文字'), findsNothing);
    expect(find.byTooltip('复制选中文字'), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final controller = viewer.controller!;
    final pageRect = controller.layout.pageLayouts[1];
    final visibleOffset =
        (controller.visibleRect.top - pageRect.top) / pageRect.height;
    expect(visibleOffset, closeTo(0.35, 0.08));
    expect(controller.currentZoom, closeTo(1.5, 0.05));
    expect(find.byTooltip('更多阅读工具'), findsOneWidget);
    await tester.tap(find.byTooltip('更多阅读工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('朗读'));
    await _pumpUntil(tester, find.byKey(const Key('tts-current-sentence')));
    expect(find.text('系统语音 · 逐句朗读'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭朗读'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.text('第一章 文本型 PDF 与坐标'), findsOneWidget);
    await tester.tap(find.text('第二章 标注定位'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 /'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-page-indicator')));
    await tester.pumpAndSettle();
    expect(find.text('跳转页码'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pdf-page-input')), '3');
    await tester.tap(find.byKey(const Key('pdf-page-jump-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 /'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-search-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('pdf-search-input')),
      'MOYE-PHASE0-ANCHOR',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntil(tester, find.textContaining('1 / 1 个结果'));
    expect(find.textContaining('2 /'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-search-input')), findsNothing);

    await tester.tap(find.byTooltip('返回书库'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('book-card-${book.id}')), findsOneWidget);
    final progress = await tester.runAsync(
      () => services.library.getProgress(book.id),
    );
    expect(progress, isNotNull);
    expect(progress!.pageNumber, greaterThanOrEqualTo(1));
    final refreshed = await tester.runAsync(
      () => services.library.findById(book.id),
    );
    expect(refreshed!.lastOpenedAt, isNotNull);
    expect(refreshed.status, BookStatus.notStarted);

    // Returning from the reader must refresh the details timestamp, not leave
    // the pre-read value in the Riverpod cache.
    await tester.tap(find.byKey(Key('book-card-${book.id}')));
    await tester.pumpAndSettle();
    expect(find.text('最近阅读'), findsOneWidget);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final recentRow = find
        .ancestor(of: find.text('最近阅读'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: recentRow, matching: find.textContaining(today)),
      findsOneWidget,
    );
  });
}
