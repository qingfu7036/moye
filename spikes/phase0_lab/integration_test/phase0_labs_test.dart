import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moye_phase0/main.dart' as app;

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
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

Future<void> _openLab(WidgetTester tester, String label) async {
  final nav = find.byKey(Key('nav-$label'));
  if (nav.evaluate().isEmpty) {
    throw TestFailure('Navigation item $label not found');
  }
  await tester.tap(nav.first);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 0 labs boot and expose real engine results',
      (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('PHASE 0'), findsWidgets);

    await _openLab(tester, 'PDF');
    await _pumpUntil(
      tester,
      find.textContaining('文字层可用（抽样） · 3 页'),
    );
    expect(find.byKey(const Key('pdf-page-label')), findsOneWidget);

    if (find.byKey(const Key('pdf-probe-button')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('pdf-details-button')));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.tap(find.byKey(const Key('pdf-probe-button')));
    await _pumpUntil(tester, find.byKey(const Key('pdf-probe-result')));
    expect(
      find.textContaining('PDFium 文字几何验证'),
      findsOneWidget,
    );
    expect(
      find.textContaining('选区回读: MOYE-PHASE0-ANCHOR'),
      findsOneWidget,
    );
    expect(find.byTooltip('yellow 高亮'), findsOneWidget);
    await tester.tap(find.byTooltip('yellow 高亮'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('已保存高亮与'), findsOneWidget);
    // Let the floating SnackBar clear so it cannot cover the TTS controls.
    await tester.pump(const Duration(seconds: 5));

    await _openLab(tester, 'EPUB');
    await _pumpUntil(tester, find.byKey(const Key('epub-title')));
    expect(
      find.textContaining('MOYE-EPUB-CFI-ANCHOR', findRichText: true),
      findsWidgets,
    );
    expect(find.byKey(const Key('epub-cfi-label')), findsOneWidget);
    final fontBefore =
        (tester.widget<Text>(find.byKey(const Key('epub-font-size')))).data;
    await tester.tap(find.byKey(const Key('epub-font-increase')));
    await tester.pump(const Duration(milliseconds: 400));
    final fontAfter =
        (tester.widget<Text>(find.byKey(const Key('epub-font-size')))).data;
    expect(fontAfter, isNot(fontBefore));
    expect(
      find.textContaining('MOYE-EPUB-CFI-ANCHOR', findRichText: true),
      findsWidgets,
    );

    await _openLab(tester, 'DOCX');
    await _pumpUntil(tester, find.byKey(const Key('docx-title')));
    expect(find.textContaining('1 个表格'), findsWidgets);
    await tester.tap(find.byKey(const Key('docx-probe')));
    await _pumpUntil(tester, find.byKey(const Key('docx-probe-result')));
    expect(find.textContaining('body/p['), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pump(const Duration(milliseconds: 300));

    await _openLab(tester, '语音');
    await _pumpUntil(
      tester,
      find.byKey(const Key('tts-voice-count')),
      timeout: const Duration(seconds: 25),
    );
    expect(find.text('0 个可用声音'), findsNothing);
    expect(find.byKey(const Key('tts-sentence-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tts-play')));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.textContaining('正在朗读第'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tts-play')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('已暂停'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tts-stop')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('待播放'), findsOneWidget);
  });
}
