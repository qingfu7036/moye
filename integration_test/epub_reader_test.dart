import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moye/app/moye_app.dart';
import 'package:moye/app/providers.dart';
import 'package:moye/core/app_services.dart';
import 'package:moye/core/database/library_database.dart';
import 'package:moye/core/epub/epub_parser.dart';
import 'package:moye/core/storage/app_paths.dart';
import 'package:moye/core/storage/book_file_store.dart';
import 'package:moye/features/library/data/library_repository.dart';
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

  testWidgets('opens an EPUB, shows its TOC and restores a chapter anchor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('moye_epub_test_'),
    );
    final paths = (await tester.runAsync(() => AppPaths.forRoot(temp!)))!;
    final services = _services(paths);
    addTearDown(() async {
      try {
        services.dispose();
      } catch (_) {}
      if (await temp!.exists()) await temp.delete(recursive: true);
    });

    final fixture =
        Platform.environment['MOYE_EPUB_TEST'] ??
        p.join('test', 'fixtures', 'sample_links.epub');
    final imported = await tester.runAsync(
      () => services.library.importFile(fixture),
    );
    final book = imported!.book!;
    final document = const EpubParser().parse(
      await File(fixture).readAsBytes(),
    );
    await tester.runAsync(
      () => services.library.saveEpubProgress(
        book.id,
        chapterIndex: 0,
        blockIndex: document.chapters.first.blocks.isEmpty ? 0 : 1,
        cfi: document.cfiFor(document.chapters.first, 0),
        chapterCount: document.chapters.length,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('book-card-${book.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-details')), findsOneWidget);
    final detailsScrollable = find
        .descendant(
          of: find.byKey(const Key('book-details')),
          matching: find.byType(Scrollable),
        )
        .first;
    // The details list is lazy; bring the reader action into the built range.
    await tester.drag(detailsScrollable, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-reader-button')), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-reader-button')));
    await _pumpUntil(tester, find.byKey(const Key('epub-chapter-indicator')));

    expect(find.textContaining(RegExp(r'第 \d+ / \d+ 章')), findsOneWidget);
    expect(find.byTooltip('目录'), findsOneWidget);
    expect(find.byTooltip('更多阅读工具'), findsOneWidget);
    await tester.tap(find.byTooltip('更多阅读工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('朗读'));
    await _pumpUntil(tester, find.byKey(const Key('tts-current-sentence')));
    expect(find.text('系统语音 · 逐句朗读'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭朗读'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多阅读工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bookmark-add-current')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 章'), findsWidgets);
    await tester.tap(find.byTooltip('关闭书签'));
    await tester.pumpAndSettle();

    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? '').contains('这是 EPUB3 验证样本的第一段'),
    );
    final beforeZoom = tester
        .widget<SelectableText>(paragraph)
        .style!
        .fontSize!;
    expect(find.byTooltip('整体放大（Ctrl+滚轮）'), findsOneWidget);
    await tester.tap(find.byTooltip('整体放大（Ctrl+滚轮）'));
    await tester.pumpAndSettle();
    final afterZoom = tester.widget<SelectableText>(paragraph).style!.fontSize!;
    expect(afterZoom, greaterThan(beforeZoom));

    final center = tester.getCenter(paragraph);
    final left = await tester.createGesture(pointer: 1);
    final right = await tester.createGesture(pointer: 2);
    await left.down(center - const Offset(30, 0));
    await right.down(center + const Offset(30, 0));
    await tester.pump();
    await left.moveTo(center - const Offset(90, 0));
    await right.moveTo(center + const Offset(90, 0));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    final afterPinch = tester
        .widget<SelectableText>(paragraph)
        .style!
        .fontSize!;
    expect(afterPinch, greaterThan(afterZoom));

    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    final tocTile = find.byType(ListTile).first;
    expect(tocTile, findsOneWidget);
    await tester.tap(tocTile);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('epub-search-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('epub-search-input')),
      'MOYE-EPUB-CFI-ANCHOR',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntil(tester, find.textContaining('1 / 1 个结果'));
    expect(find.textContaining('第 1 /'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('epub-search-input')), '查看脚注');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntil(tester, find.textContaining('1 / 1 个结果'));
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.text('脚注 查看脚注'), findsOneWidget);
    await tester.tap(find.text('脚注 查看脚注'));
    await tester.pumpAndSettle();
    expect(find.text('脚注'), findsOneWidget);
    expect(find.textContaining('这是脚注内容'), findsWidgets);
    await tester.tap(find.byKey(const Key('epub-link-target-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('epub-search-input')), '表格渲染');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntil(tester, find.textContaining('1 / 1 个结果'));
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.text('表格渲染'), findsOneWidget);
    expect(find.text('通过'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('epub-search-input')), '漢字');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntil(tester, find.textContaining('1 / 1 个结果'));
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.textSpan?.toPlainText().contains('かんじ') ?? false),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('返回书库'));
    await tester.pumpAndSettle();
    final progress = await tester.runAsync(
      () => services.library.getProgress(book.id),
    );
    expect(progress, isNotNull);
    expect(progress!.anchorJson, isNotNull);
    final anchor = jsonDecode(progress.anchorJson!) as Map;
    expect(anchor['chapter'], isA<num>());
    expect(anchor['cfi'], isA<String>());
  });
}
