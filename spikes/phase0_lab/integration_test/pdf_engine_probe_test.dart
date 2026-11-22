import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  testWidgets('PDFium text geometry and scanned-PDF detection',
      (tester) async {
    await tester.runAsync(() async {
      final textDocument =
          await PdfDocument.openAsset('assets/fixtures/sample.pdf');
      // ignore: avoid_print
      print('PDF_PAGES=${textDocument.pages.length}');
      // ignore: avoid_print
      print('PDF_PAGE_SIZE=${textDocument.pages.first.width}x'
          '${textDocument.pages.first.height}');

      final pageText = await textDocument.pages[1]
          .loadStructuredText(ensureLoaded: true);
      const marker = 'MOYE-PHASE0-ANCHOR';
      final start = pageText.fullText.indexOf(marker);
      // ignore: avoid_print
      print('PDF_TEXT_CHARS=${pageText.fullText.length}');
      // ignore: avoid_print
      print('PDF_MARKER_START=$start');
      expect(start, greaterThanOrEqualTo(0));
      final range =
          pageText.getRangeFromAB(start, start + marker.length - 1);
      final rects = range.enumerateFragmentBoundingRects().toList();
      // ignore: avoid_print
      print('PDF_SELECTION=${range.start}..${range.end}');
      // ignore: avoid_print
      print('PDF_SELECTION_TEXT=${range.text}');
      // ignore: avoid_print
      print('PDF_FRAGMENT_RECTS=${rects.length}');
      for (final fragment in rects) {
        // ignore: avoid_print
        print('PDF_RECT=${fragment.bounds}');
      }
      expect(rects, isNotEmpty);
      textDocument.dispose();

      final scannedDocument =
          await PdfDocument.openAsset('assets/fixtures/scanned.pdf');
      final scannedText = await scannedDocument.pages.first
          .loadStructuredText(ensureLoaded: true);
      // ignore: avoid_print
      print('SCANNED_TEXT_CHARS=${scannedText.fullText.trim().length}');
      expect(scannedText.fullText.trim().length, lessThan(20));
      scannedDocument.dispose();
    });
  });
}
