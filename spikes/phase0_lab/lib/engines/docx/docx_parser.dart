import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'docx_models.dart';

class DocxParseException implements Exception {
  const DocxParseException(this.message);
  final String message;

  @override
  String toString() => 'DocxParseException: $message';
}

class DocxParser {
  const DocxParser();

  DocxDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw DocxParseException('不是有效的 DOCX/ZIP 文件：$error');
    }

    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) files[_normalise(file.name)] = file;
    }

    final documentFile = files['word/document.xml'];
    if (documentFile == null) {
      throw const DocxParseException('缺少 word/document.xml');
    }
    final documentXml = _parseXml(documentFile);
    final body = documentXml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'body')
        .firstOrNull;
    if (body == null) {
      throw const DocxParseException('document.xml 中没有 body');
    }

    final styles = _parseStyles(files['word/styles.xml']);
    final relationships = _parseRelationships(files['word/_rels/document.xml.rels']);
    final blocks = <DocxBlock>[];
    final paragraphOrdinals = <XmlElement, int>{};
    var paragraphOrdinal = 0;
    var tableOrdinal = 0;

    for (final child in body.children.whereType<XmlElement>()) {
      switch (child.localName) {
        case 'p':
          final path = 'body/p[${++paragraphOrdinal}]';
          paragraphOrdinals[child] = paragraphOrdinal;
          blocks.addAll(_parseParagraph(child, path, styles, relationships, files));
        case 'tbl':
          final path = 'body/tbl[${++tableOrdinal}]';
          final table = _parseTable(child);
          blocks.add(DocxBlock(
            kind: DocxBlockKind.table,
            text: table.rows.map((row) => row.join(' | ')).join('\n'),
            path: path,
            table: table,
          ));
      }
    }

    final plainBuffer = StringBuffer();
    final starts = <int>[];
    for (final block in blocks) {
      starts.add(plainBuffer.length);
      plainBuffer.write(block.text);
      plainBuffer.write('\n');
    }
    final plainText = plainBuffer.toString();
    final core = _parseCore(files['docProps/core.xml']);
    final firstHeading = blocks
        .where((block) => block.isHeading && block.text.trim().isNotEmpty)
        .map((block) => block.text.trim())
        .firstOrNull;

    return DocxDocument(
      title: core.title ?? firstHeading ?? p.basenameWithoutExtension('document.docx'),
      author: core.author ?? '未知作者',
      blocks: blocks,
      plainText: plainText,
      blockStarts: starts,
    );
  }

  List<DocxBlock> _parseParagraph(
    XmlElement paragraph,
    String path,
    Map<String, _StyleInfo> styles,
    Map<String, String> relationships,
    Map<String, ArchiveFile> files,
  ) {
    final pPr = _directChild(paragraph, 'pPr');
    final styleId = _attributeOfDescendant(pPr, 'pStyle', 'val') ?? '';
    final style = styles[styleId];
    final directOutlineLevel =
        int.tryParse(_attributeOfDescendant(pPr, 'outlineLvl', 'val') ?? '');
    final outlineLevel = directOutlineLevel ?? style?.outlineLevel;
    final styleName = style?.name ?? styleId;
    final numId = _attributeOfDescendant(pPr, 'numId', 'val');
    final numLevel = int.tryParse(
      _attributeOfDescendant(pPr, 'ilvl', 'val') ?? '0',
    );

    final buffer = StringBuffer();
    final links = <DocxLink>[];
    final images = <DocxImage>[];

    void visit(XmlNode node) {
      if (node is! XmlElement) {
        if (node is XmlText) buffer.write(node.value);
        return;
      }
      switch (node.localName) {
        case 't':
          buffer.write(node.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br' || 'cr':
          buffer.write('\n');
        case 'hyperlink':
          final before = buffer.length;
          final relId = _attr(node, 'id') ?? '';
          final anchor = _attr(node, 'anchor');
          for (final child in node.children) {
            visit(child);
          }
          final linkText = buffer.toString().substring(before);
          final target = relationships[relId] ?? (anchor == null ? '' : '#$anchor');
          if (linkText.isNotEmpty && target.isNotEmpty) {
            links.add(DocxLink(text: linkText, target: target));
          }
        case 'drawing':
          for (final blip in node.descendants.whereType<XmlElement>()) {
            if (blip.localName != 'blip') continue;
            final relId = _attr(blip, 'embed') ?? '';
            final target = relationships[relId];
            if (target == null) continue;
            final file = files[_normalise(p.posix.join('word', target))];
            final imageBytes = file?.readBytes();
            if (imageBytes != null) {
              images.add(DocxImage(
                bytes: imageBytes,
                relationshipId: relId,
                alt: _attr(blip, 'descr') ?? '',
              ));
            }
          }
        default:
          for (final child in node.children) {
            visit(child);
          }
      }
    }

    for (final child in paragraph.children) {
      visit(child);
    }

    final text = buffer.toString().replaceAll('\u00a0', ' ').trim();
    final kind = _kindFor(styleName, outlineLevel, numId != null);
    final blocks = <DocxBlock>[
      DocxBlock(
        kind: kind,
        text: text,
        path: path,
        styleId: styleId,
        styleName: styleName,
        outlineLevel: outlineLevel,
        numberingId: numId,
        numberingLevel: numId == null ? null : numLevel,
        links: links,
      ),
    ];
    for (var i = 0; i < images.length; i++) {
      blocks.add(DocxBlock(
        kind: DocxBlockKind.image,
        text: '',
        path: '$path/image[${i + 1}]',
        image: images[i],
      ));
    }
    return blocks;
  }

  DocxTable _parseTable(XmlElement table) {
    final rows = <List<String>>[];
    for (final row in table.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'tr',
    )) {
      final cells = <String>[];
      for (final cell in row.children.whereType<XmlElement>()) {
        if (cell.localName != 'tc') continue;
        final text = cell.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'p')
            .map((paragraph) => paragraph.innerText.trim())
            .where((value) => value.isNotEmpty)
            .join(' ');
        cells.add(text);
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return DocxTable(rows: rows);
  }

  static DocxBlockKind _kindFor(
    String styleName,
    int? outlineLevel,
    bool isList,
  ) {
    final lower = styleName.toLowerCase();
    final match = RegExp(r'(?:heading|标题)\s*([1-6])').firstMatch(lower);
    final level = match == null ? null : int.tryParse(match.group(1)!);
    final resolved = level ?? (outlineLevel == null ? null : outlineLevel + 1);
    if (resolved != null && resolved >= 1 && resolved <= 6) {
      return DocxBlockKind.values[resolved];
    }
    if (lower.contains('quote') || lower.contains('引用')) {
      return DocxBlockKind.quote;
    }
    if (isList || lower.contains('list')) return DocxBlockKind.listItem;
    return DocxBlockKind.paragraph;
  }

  static Map<String, _StyleInfo> _parseStyles(ArchiveFile? file) {
    if (file == null) return const {};
    final document = _parseXml(file);
    final result = <String, _StyleInfo>{};
    for (final style in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'style',
    )) {
      if (_attr(style, 'type') != 'paragraph') continue;
      final id = _attr(style, 'styleId');
      if (id == null) continue;
      final name = _attributeOfDescendant(style, 'name', 'val') ?? id;
      final outline = int.tryParse(
        _attributeOfDescendant(style, 'outlineLvl', 'val') ?? '',
      );
      result[id] = _StyleInfo(name: name, outlineLevel: outline);
    }
    return result;
  }

  static Map<String, String> _parseRelationships(ArchiveFile? file) {
    if (file == null) return const {};
    final document = _parseXml(file);
    final result = <String, String>{};
    for (final relationship in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'Relationship',
    )) {
      final id = _attr(relationship, 'Id');
      final target = _attr(relationship, 'Target');
      if (id == null || target == null) continue;
      result[id] = target.replaceAll('\\', '/');
    }
    return result;
  }

  static _CoreInfo _parseCore(ArchiveFile? file) {
    if (file == null) return const _CoreInfo();
    final document = _parseXml(file);
    return _CoreInfo(
      title: _elementText(document, 'title'),
      author: _elementText(document, 'creator'),
    );
  }

  static String? _elementText(XmlDocument document, String localName) {
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName && element.innerText.trim().isNotEmpty) {
        return element.innerText.trim();
      }
    }
    return null;
  }

  static XmlElement? _directChild(XmlElement? parent, String localName) {
    if (parent == null) return null;
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.localName == localName) return child;
    }
    return null;
  }

  static String? _attr(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String? _attributeOfDescendant(
    XmlElement? parent,
    String localName,
    String attribute,
  ) {
    if (parent == null) return null;
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.localName == localName) {
        return element.getAttribute('w:$attribute') ??
            element.getAttribute(attribute);
      }
    }
    return null;
  }

  static XmlDocument _parseXml(ArchiveFile file) {
    try {
      return XmlDocument.parse(utf8.decode(file.readBytes()!, allowMalformed: true));
    } catch (error) {
      throw DocxParseException('XML 解析失败：${file.name}: $error');
    }
  }

  static String _normalise(String value) =>
      p.posix.normalize(value.replaceAll('\\', '/'));
}

class _StyleInfo {
  const _StyleInfo({required this.name, this.outlineLevel});
  final String name;
  final int? outlineLevel;
}

class _CoreInfo {
  const _CoreInfo({this.title, this.author});
  final String? title;
  final String? author;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
