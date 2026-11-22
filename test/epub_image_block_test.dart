import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moye/features/reader/presentation/widgets/epub_image_block.dart';

final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 300, child: child)),
);

void main() {
  testWidgets('scales an EPUB image with the text and scrolls when oversized', (
    tester,
  ) async {
    await tester.pumpWidget(_host(EpubImageBlock(bytes: _pixel, scale: 1.5)));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 450);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .scrollDirection,
      Axis.horizontal,
    );
  });

  testWidgets('shrinks an EPUB image without adding horizontal scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(_host(EpubImageBlock(bytes: _pixel, scale: 0.5)));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 150);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.physics, isA<NeverScrollableScrollPhysics>());
    expect(find.byType(Center), findsOneWidget);
  });

  testWidgets('only the explicit image button opens the full-screen view', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(EpubImageBlock(bytes: _pixel, scale: 1, onTap: () => taps++)),
    );
    await tester.pump();

    await tester.tap(find.byType(Image));
    expect(taps, 0);
    await tester.tap(find.byTooltip('全屏查看图片'));
    expect(taps, 1);
  });
}
