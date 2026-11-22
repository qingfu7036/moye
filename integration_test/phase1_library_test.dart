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
import 'package:moye/features/library/data/book_picker.dart';
import 'package:moye/features/library/data/library_repository.dart';
import 'package:path/path.dart' as p;

class _FixturePicker implements BookPicker {
  _FixturePicker(this.files);

  final List<File> files;

  @override
  Future<List<PickedBookSource>> pickBooks() async {
    return [
      for (final file in files)
        PickedBookSource(
          name: p.basename(file.path),
          openStream: () => file.openRead(),
        ),
    ];
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'Timed out waiting for ${finder.describeMatch(Plurality.many)}',
  );
}

AppServices _services(AppPaths paths) {
  final database = LibraryDatabase.open(paths.databaseFile);
  final repository = LibraryRepository(
    database: database,
    paths: paths,
    files: BookFileStore(paths),
  );
  return AppServices(paths: paths, database: database, library: repository);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 1 imports, reopens and deletes a real book via the UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('moye_phase1_integration_'),
    );
    final paths = (await tester.runAsync(() => AppPaths.forRoot(temp!)))!;
    var services = _services(paths);
    addTearDown(() async {
      try {
        services.dispose();
      } catch (_) {}
      if (await temp!.exists()) await temp.delete(recursive: true);
    });

    final fixture = File(p.join('test', 'fixtures', 'sample.pdf'));
    final picker = _FixturePicker([fixture]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          bookPickerProvider.overrideWithValue(picker),
        ],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-books-button')));
    await _pumpUntil(tester, find.text('1 本'));
    expect(find.byKey(const Key('library-import-summary')), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    final imported = (await tester.runAsync(services.library.listBooks))!
        .single;
    expect(imported.format.name, 'pdf');
    expect(imported.coverPath, isNotNull);
    expect(
      await tester.runAsync(
        () => paths.resolveRelative(imported.relativePath).exists(),
      ),
      isTrue,
    );

    await tester.tap(find.byKey(Key('book-card-${imported.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-details')), findsOneWidget);
    expect(find.text(imported.title), findsWidgets);

    // Close the app, reopen the same data directory, and confirm persistence.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    services.dispose();
    services = _services(paths);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 本'), findsOneWidget);
    expect(find.byKey(Key('book-card-${imported.id}')), findsOneWidget);

    // Delete from the details panel and verify both row and private file.
    await tester.tap(find.byKey(Key('book-card-${imported.id}')));
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
    await tester.drag(detailsScrollable, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从书库删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _pumpUntil(tester, find.byKey(const Key('library-empty')));
    expect(await tester.runAsync(services.library.listBooks), isEmpty);
    expect(
      await tester.runAsync(
        () => paths.resolveRelative(imported.relativePath).exists(),
      ),
      isFalse,
    );
    expect(
      await tester.runAsync(
        () => paths.resolveRelative(imported.coverPath!).exists(),
      ),
      isFalse,
    );
  });
}
