import 'dart:typed_data';

enum DocxBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  listItem,
  quote,
  image,
  table,
}

class DocxImage {
  const DocxImage({
    required this.bytes,
    required this.relationshipId,
    this.alt = '',
  });

  final Uint8List bytes;
  final String relationshipId;
  final String alt;
}

class DocxTable {
  const DocxTable({required this.rows});

  /// Cell text only. Phase 0 verifies table extraction and positioning; the V1
  /// renderer will retain merged-cell and cell-property metadata.
  final List<List<String>> rows;
}

class DocxBlock {
  const DocxBlock({
    required this.kind,
    required this.text,
    required this.path,
    this.styleId = '',
    this.styleName = '',
    this.outlineLevel,
    this.numberingId,
    this.numberingLevel,
    this.image,
    this.table,
    this.links = const [],
  });

  final DocxBlockKind kind;
  final String text;
  final String path;
  final String styleId;
  final String styleName;
  final int? outlineLevel;
  final String? numberingId;
  final int? numberingLevel;
  final DocxImage? image;
  final DocxTable? table;
  final List<DocxLink> links;

  bool get isHeading => kind != DocxBlockKind.paragraph &&
      kind != DocxBlockKind.listItem &&
      kind != DocxBlockKind.quote &&
      kind != DocxBlockKind.image &&
      kind != DocxBlockKind.table;

  int? get headingLevel {
    if (!isHeading) return null;
    return kind.index; // heading1 == 1, ... heading6 == 6
  }
}

class DocxLink {
  const DocxLink({required this.text, required this.target});

  final String text;
  final String target;
}

class DocxDocument {
  DocxDocument({
    required this.title,
    required this.author,
    required this.blocks,
    required this.plainText,
    required this.blockStarts,
  });

  final String title;
  final String author;
  final List<DocxBlock> blocks;

  /// Paragraph text joined with newlines. Kept separate from rendered widgets so
  /// TTS and search can run without walking the widget tree.
  final String plainText;

  /// UTF-16 offset of each block in [plainText].
  final List<int> blockStarts;

  String textForBlock(int index) =>
      index >= 0 && index < blocks.length ? blocks[index].text : '';

  int startForBlock(int index) =>
      index >= 0 && index < blockStarts.length ? blockStarts[index] : 0;
}
