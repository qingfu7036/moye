import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moye_phase0/core/reading_anchor.dart';
import 'package:moye_phase0/core/sentence_segmenter.dart';
import 'package:moye_phase0/engines/docx/docx_document.dart';
import 'package:moye_phase0/engines/epub/epub_document.dart';

void main() {
  group('sentence segmenter', () {
    test('preserves offsets for mixed Chinese and English', () {
      const text = '第一句。第二句！The quick brown fox jumps over the lazy dog. 最后一句';
      final spans = SentenceSegmenter.split(text);
      expect(spans.length, 4);
      expect(spans[0].text, '第一句。');
      expect(spans[0].start, 0);
      expect(text.substring(spans[1].start, spans[1].end), '第二句！');
      expect(spans[2].text, contains('The quick brown fox'));
      expect(spans.last.text, '最后一句');
      for (final span in spans) {
        expect(text.substring(span.start, span.end), span.text);
      }
    });

    test('does not split decimal numbers or chunk long prose unboundedly', () {
      final spans = SentenceSegmenter.split('版本 1.0 很好。${'甲' * 600}');
      expect(spans.first.text, '版本 1.0 很好。');
      expect(spans.skip(1).every((span) => span.text.length <= 280), isTrue);
    });
  });

  group('anchor and context', () {
    test('round-trips JSON without dropping geometry', () {
      final anchor = ReadingAnchor(
        format: BookFormat.pdf,
        quote: '选择这段文字',
        page: 3,
        pageStart: 120,
        pageEnd: 126,
        contextBefore: '前面',
        contextAfter: '后面',
        pdfRects: const [PdfRectData(10, 20, 30, 5)],
        textHash: 'abc',
      );
      final restored = ReadingAnchor.fromJson(anchor.toJson());
      expect(restored.quote, anchor.quote);
      expect(restored.page, 3);
      expect(restored.pdfRects.single.right, 30);
      expect(restored.contextAfter, '后面');
    });

    test('uses context to disambiguate repeated quotes', () {
      const text = '前言甲，重要文字，后文一。前言乙，重要文字，后文二。';
      const anchor = ReadingAnchor(
        format: BookFormat.epub,
        quote: '重要文字',
        charOffset: 20,
        contextBefore: '前言乙，',
        contextAfter: '，后文二',
      );
      final match = Anchoring.find(text, anchor);
      expect(match, isNotNull);
      expect(match!.start, text.indexOf('重要文字', 10));
      expect(match.confidence, greaterThan(0.6));
    });
  });

  group('EPUB parser', () {
    late EpubDocument book;

    setUpAll(() {
      final bytes = File('assets/fixtures/sample.epub').readAsBytesSync();
      book = const EpubParser().parse(bytes);
    });

    test('reads EPUB3 metadata, spine, TOC and cover', () {
      expect(book.title, '墨页 EPUB3 验证样本');
      expect(book.author, 'MOYE Phase 0');
      expect(book.chapters.length, 2);
      expect(book.toc.length, 2);
      expect(book.toc.first.title, contains('动态排版'));
      expect(book.coverBytes, isNotNull);
    });

    test('extracts stable CFI paths and paragraph text', () {
      final chapter = book.chapters.first;
      expect(chapter.plainText, contains('MOYE-EPUB-CFI-ANCHOR'));
      expect(chapter.blocks.first.kind, EpubBlockKind.heading1);
      final anchorBlock = chapter.blocks.indexWhere(
        (block) => block.text.contains('MOYE-EPUB-CFI-ANCHOR'),
      );
      final cfi = book.cfiFor(chapter, anchorBlock, charOffset: 4);
      expect(cfi, 'epubcfi(/6/2[ch1]!/4/2/6/1:4)');
      expect(cfi, endsWith(':4)'));
    });
  });

  group('DOCX parser', () {
    late DocxDocument docx;

    setUpAll(() {
      final bytes = File('assets/fixtures/sample.docx').readAsBytesSync();
      docx = const DocxParser().parse(bytes);
    });

    test('preserves headings, lists, table, hyperlink and image', () {
      expect(docx.title, '墨页 DOCX 验证样本');
      expect(docx.author, 'MOYE Phase 0');
      expect(docx.blocks.any((block) => block.kind == DocxBlockKind.heading1), isTrue);
      expect(docx.blocks.any((block) => block.kind == DocxBlockKind.listItem), isTrue);
      expect(docx.blocks.any((block) => block.kind == DocxBlockKind.table), isTrue);
      expect(docx.blocks.any((block) => block.kind == DocxBlockKind.image), isTrue);
      final link = docx.blocks.expand((block) => block.links).firstWhere(
            (link) => link.text.contains('Flutter'),
          );
      expect(link.target, 'https://flutter.dev');
      final table = docx.blocks
          .firstWhere((block) => block.kind == DocxBlockKind.table)
          .table!;
      expect(table.rows.expand((row) => row), contains('PDFium 文字选择'));
    });

    test('keeps paragraph paths and text offsets aligned', () {
      final index = docx.blocks.indexWhere(
        (block) => block.text.contains('MOYE-DOCX-PARAGRAPH-ANCHOR'),
      );
      expect(index, greaterThan(0));
      expect(docx.blocks[index].path, matches(r'body/p\[\d+\]'));
      expect(docx.blockStarts.length, docx.blocks.length);
      expect(
        docx.plainText.substring(docx.startForBlock(index)),
        startsWith('唯一段落标记'),
      );
    });
  });
}
