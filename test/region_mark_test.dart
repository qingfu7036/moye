import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moye/features/reader/presentation/widgets/region_mark_layer.dart';

void main() {
  testWidgets('captures a selected rectangle as a PNG', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 180,
          child: RegionMarkLayer(
            boundaryKey: key,
            marking: false,
            annotations: const [],
            onSelected: (_) {},
            onAnnotationTap: (_) {},
            onCancel: () {},
            child: Container(color: Colors.orange),
          ),
        ),
      ),
    );
    final bytes = await tester.runAsync(
      () => captureRegion(key, const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4)),
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(20));
  });
}
