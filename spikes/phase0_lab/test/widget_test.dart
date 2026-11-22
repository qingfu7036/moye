import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moye_phase0/app/moye_theme.dart';
import 'package:moye_phase0/app/overview_page.dart';

void main() {
  testWidgets('overview renders the Phase 0 risk dashboard', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: moyeTheme(Brightness.light),
        home: const OverviewPage(onOpenLab: _ignoreLab),
      ),
    );

    expect(find.textContaining('PHASE 0'), findsWidgets);
    expect(find.text('运行环境'), findsOneWidget);
    expect(find.textContaining('PDF'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _ignoreLab(int index) {}
