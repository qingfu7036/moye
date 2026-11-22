import 'dart:io';

import 'package:moye_phase0/engines/docx/docx_document.dart';
import 'package:moye_phase0/engines/epub/epub_document.dart';

void main() {
  final epub = const EpubParser()
      .parse(File('assets/fixtures/sample.epub').readAsBytesSync());
  stdout.writeln('EPUB_TITLE=${epub.title}');
  stdout.writeln('EPUB_AUTHOR=${epub.author}');
  stdout.writeln('EPUB_CHAPTERS=${epub.chapters.length}');
  stdout.writeln('EPUB_TOC=${epub.toc.map((entry) => entry.title).join(' | ')}');
  for (final chapter in epub.chapters) {
    final index = chapter.blocks.indexWhere(
      (block) => block.text.contains('MOYE-EPUB-CFI-ANCHOR'),
    );
    stdout.writeln('EPUB_CHAPTER_${chapter.index}=${chapter.title}');
    if (index >= 0) {
      final block = chapter.blocks[index];
      stdout.writeln('EPUB_MARKER_BLOCK=$index');
      stdout.writeln('EPUB_MARKER_CFI=${epub.cfiFor(chapter, index, charOffset: 4)}');
      stdout.writeln('EPUB_MARKER_TEXT=${block.text}');
    }
  }
  stdout.writeln('EPUB_COVER_BYTES=${epub.coverBytes?.length ?? 0}');

  final docx = const DocxParser()
      .parse(File('assets/fixtures/sample.docx').readAsBytesSync());
  stdout.writeln('DOCX_TITLE=${docx.title}');
  stdout.writeln('DOCX_AUTHOR=${docx.author}');
  stdout.writeln('DOCX_BLOCKS=${docx.blocks.length}');
  stdout.writeln(
      'DOCX_KINDS=${docx.blocks.map((block) => block.kind.name).join(',')}');
  final markerIndex = docx.blocks.indexWhere(
    (block) => block.text.contains('MOYE-DOCX-PARAGRAPH-ANCHOR'),
  );
  final marker = docx.blocks[markerIndex];
  stdout.writeln('DOCX_MARKER_PATH=${marker.path}');
  stdout.writeln(
      'DOCX_MARKER_OFFSET=${marker.text.indexOf('MOYE-DOCX-PARAGRAPH-ANCHOR')}');
  stdout.writeln('DOCX_MARKER_TEXT=${marker.text}');
  stdout.writeln(
      'DOCX_LINKS=${docx.blocks.expand((block) => block.links).map((link) => '${link.text}=>${link.target}').join(' | ')}');
  final table =
      docx.blocks.firstWhere((block) => block.kind == DocxBlockKind.table);
  stdout.writeln('DOCX_TABLE=${table.table!.rows.map((row) => row.join('/')).join(' ; ')}');
  stdout.writeln(
      'DOCX_IMAGES=${docx.blocks.where((block) => block.kind == DocxBlockKind.image).length}');
}
