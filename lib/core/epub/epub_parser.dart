import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

enum EpubBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  listItem,
  quote,
  code,
  image,
  table,
}

class EpubLink {
  const EpubLink({
    required this.start,
    required this.end,
    required this.target,
  });

  final int start;
  final int end;

  /// Normalized chapter path plus optional `#fragment`, or an external URL.
  final String target;
}

class EpubRuby {
  const EpubRuby({
    required this.start,
    required this.end,
    required this.annotation,
  });

  final int start;
  final int end;
  final String annotation;
}

class EpubTableCell {
  const EpubTableCell({
    required this.text,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.isHeader = false,
  });

  final String text;
  final int colSpan;
  final int rowSpan;
  final bool isHeader;
}

class EpubBlock {
  const EpubBlock({
    required this.kind,
    required this.text,
    required this.cfiPath,
    this.imageBytes,
    this.imageAlt = '',
    this.links = const [],
    this.rubies = const [],
    this.tableRows = const [],
    this.tableHeaderRows = 0,
  });

  final EpubBlockKind kind;
  final String text;
  final String cfiPath;
  final Uint8List? imageBytes;
  final String imageAlt;
  final List<EpubLink> links;
  final List<EpubRuby> rubies;
  final List<List<EpubTableCell>> tableRows;
  final int tableHeaderRows;
}

class EpubChapter {
  EpubChapter({
    required this.index,
    required this.idref,
    required this.href,
    required this.title,
    required this.blocks,
    required this.cfiBase,
    this.anchors = const {},
  }) : blockStarts = _computeStarts(blocks),
       plainText = blocks
           .where((block) => block.kind != EpubBlockKind.image)
           .map((block) => block.text)
           .join('\n');

  static List<int> _computeStarts(List<EpubBlock> blocks) {
    final starts = <int>[];
    var offset = 0;
    for (final block in blocks) {
      starts.add(offset);
      if (block.kind == EpubBlockKind.image) continue;
      offset += block.text.length + 1;
    }
    return starts;
  }

  final int index;
  final String idref;
  final String href;
  final String title;
  final List<EpubBlock> blocks;
  final String cfiBase;
  final Map<String, int> anchors;
  final String plainText;
  final List<int> blockStarts;

  int startForBlock(int index) =>
      index >= 0 && index < blockStarts.length ? blockStarts[index] : 0;
}

class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.href,
    required this.chapterIndex,
  });

  final String title;
  final String href;
  final int chapterIndex;
}

class EpubDocument {
  EpubDocument({
    required this.title,
    required this.author,
    required this.language,
    required this.identifier,
    required this.chapters,
    required this.toc,
    required this.resourceCount,
    this.coverBytes,
  });

  final String title;
  final String author;
  final String language;
  final String identifier;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> toc;
  final int resourceCount;
  final Uint8List? coverBytes;

  String cfiFor(EpubChapter chapter, int blockIndex, {int charOffset = 0}) {
    if (blockIndex < 0 || blockIndex >= chapter.blocks.length) {
      return chapter.cfiBase;
    }
    final path = chapter.blocks[blockIndex].cfiPath;
    final offsetSuffix = charOffset > 0 ? '/1:$charOffset' : '';
    final base = chapter.cfiBase;
    // cfiBase is a complete CFI for the document root; insert the element path
    // before its closing parenthesis instead of producing `...)/2/...`.
    return '${base.substring(0, base.length - 1)}$path$offsetSuffix)';
  }
}

class EpubParseException implements Exception {
  const EpubParseException(this.message);
  final String message;

  @override
  String toString() => 'EpubParseException: $message';
}

class EpubParser {
  const EpubParser();

  EpubDocument parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw EpubParseException('不是有效的 EPUB/ZIP 文件：$error');
    }

    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) {
        files[_normalise(file.name)] = file;
      }
    }

    final containerFile = _findFile(files, 'META-INF/container.xml');
    if (containerFile == null) {
      throw const EpubParseException('缺少 META-INF/container.xml');
    }
    final containerXml = _parseXml(containerFile);
    final rootfile = containerXml
        .findAllElements('rootfile')
        .where((element) => element.getAttribute('full-path') != null)
        .firstOrNull;
    if (rootfile == null) {
      throw const EpubParseException('container.xml 中没有 rootfile');
    }
    final opfPath = _normalise(rootfile.getAttribute('full-path')!);
    final opfFile = files[opfPath];
    if (opfFile == null) {
      throw EpubParseException('找不到 OPF：$opfPath');
    }
    final opf = _parseXml(opfFile);
    final opfDir = p.posix.dirname(opfPath);

    final metadata = opf.findAllElements('metadata').firstOrNull;
    final title =
        _metadataText(metadata, 'title') ?? p.basenameWithoutExtension(opfPath);
    final author = _metadataText(metadata, 'creator') ?? '未知作者';
    final language = _metadataText(metadata, 'language') ?? 'und';
    final identifier = _metadataText(metadata, 'identifier') ?? title;

    final manifest = <String, _ManifestItem>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _ManifestItem(
        id: id,
        href: _resolve(opfDir, href),
        mediaType: item.getAttribute('media-type') ?? '',
        properties: item.getAttribute('properties') ?? '',
      );
    }

    final spineElement = opf.findAllElements('spine').firstOrNull;
    if (spineElement == null) {
      throw const EpubParseException('OPF 中没有 spine');
    }
    final spineRefs = spineElement
        .findAllElements('itemref')
        .map((element) => element.getAttribute('idref'))
        .whereType<String>()
        .toList();

    final toc = <EpubTocEntry>[];
    final chapters = <EpubChapter>[];
    for (var index = 0; index < spineRefs.length; index++) {
      final idref = spineRefs[index];
      final item = manifest[idref];
      if (item == null) continue;
      final file = files[_normalise(item.href)];
      if (file == null) {
        throw EpubParseException('spine 引用的文件不存在：${item.href}');
      }
      final content = _parseHtml(file);
      final extracted = _extractBlocks(content, item.href, files);
      final blocks = extracted.blocks;
      final chapter = EpubChapter(
        index: chapters.length,
        idref: idref,
        href: item.href,
        title: _firstHeading(blocks) ?? p.basenameWithoutExtension(item.href),
        blocks: blocks,
        anchors: extracted.anchors,
        cfiBase: 'epubcfi(/6/${(index + 1) * 2}[$idref]!/4)',
      );
      chapters.add(chapter);
    }

    final navItem = manifest.values
        .where((item) => item.properties.split(RegExp(r'\s+')).contains('nav'))
        .firstOrNull;
    if (navItem != null) {
      final navFile = files[_normalise(navItem.href)];
      if (navFile != null) {
        toc.addAll(_parseNav(_parseHtml(navFile), chapters, navItem.href));
      }
    }
    if (toc.isEmpty) {
      final ncxItem = manifest.values
          .where(
            (item) =>
                item.mediaType == 'application/x-dtbncx+xml' ||
                item.href.toLowerCase().endsWith('.ncx'),
          )
          .firstOrNull;
      if (ncxItem != null) {
        final ncxFile = files[_normalise(ncxItem.href)];
        if (ncxFile != null) {
          toc.addAll(_parseNcx(_parseXml(ncxFile), chapters, ncxItem.href));
        }
      }
    }
    if (toc.isEmpty) {
      toc.addAll(
        chapters.map(
          (chapter) => EpubTocEntry(
            title: chapter.title,
            href: chapter.href,
            chapterIndex: chapter.index,
          ),
        ),
      );
    }

    Uint8List? coverBytes;
    final coverItem = manifest.values
        .where(
          (item) =>
              item.properties.split(RegExp(r'\s+')).contains('cover-image'),
        )
        .firstOrNull;
    if (coverItem != null) {
      coverBytes = files[_normalise(coverItem.href)]?.readBytes();
    }

    return EpubDocument(
      title: title,
      author: author,
      language: language,
      identifier: identifier,
      chapters: chapters,
      toc: toc,
      resourceCount: files.length,
      coverBytes: coverBytes,
    );
  }

  static String? _metadataText(XmlElement? metadata, String localName) {
    if (metadata == null) return null;
    for (final element in metadata.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName &&
          element.innerText.trim().isNotEmpty) {
        return element.innerText.trim();
      }
    }
    return null;
  }

  static XmlDocument _parseXml(ArchiveFile file) {
    try {
      return XmlDocument.parse(
        utf8.decode(file.readBytes()!, allowMalformed: true),
      );
    } catch (error) {
      throw EpubParseException('XML 解析失败：${file.name}: $error');
    }
  }

  static dom.Document _parseHtml(ArchiveFile file) {
    try {
      return html_parser.parse(
        utf8.decode(file.readBytes()!, allowMalformed: true),
      );
    } catch (error) {
      throw EpubParseException('XHTML 解析失败：${file.name}: $error');
    }
  }

  static ({List<EpubBlock> blocks, Map<String, int> anchors}) _extractBlocks(
    dom.Document document,
    String chapterHref,
    Map<String, ArchiveFile> files,
  ) {
    final blocks = <EpubBlock>[];
    final anchors = <String, int>{};
    final body = document.body;
    if (body == null) return (blocks: blocks, anchors: anchors);
    final chapterDir = p.posix.dirname(chapterHref);

    void addElement(dom.Element element, List<int> path) {
      final tag = element.localName?.toLowerCase() ?? '';
      final kind = switch (tag) {
        'h1' => EpubBlockKind.heading1,
        'h2' => EpubBlockKind.heading2,
        'h3' || 'h4' || 'h5' || 'h6' => EpubBlockKind.heading3,
        'li' => EpubBlockKind.listItem,
        'blockquote' => EpubBlockKind.quote,
        'pre' || 'code' => EpubBlockKind.code,
        _ => EpubBlockKind.paragraph,
      };
      final inline = _textAndLinks(element, chapterHref);
      final text = inline.text;
      final firstBlock = blocks.length;
      final cfiPath = '/${path.map((step) => (step * 2).toString()).join('/')}';
      if (text.isNotEmpty) {
        blocks.add(
          EpubBlock(
            kind: kind,
            text: text,
            cfiPath: cfiPath,
            links: inline.links,
            rubies: inline.rubies,
          ),
        );
      }
      for (final idElement in [element, ...element.querySelectorAll('[id]')]) {
        final id = idElement.attributes['id'];
        if (id != null && id.isNotEmpty) {
          anchors.putIfAbsent(id, () => firstBlock);
        }
      }
      for (final image in element.querySelectorAll('img')) {
        final src = image.attributes['src'];
        if (src == null || src.isEmpty) continue;
        final resolved = _resolve(chapterDir, src);
        final bytes = files[_normalise(resolved)]?.readBytes();
        if (bytes == null) continue;
        blocks.add(
          EpubBlock(
            kind: EpubBlockKind.image,
            text: '',
            cfiPath: cfiPath,
            imageBytes: bytes,
            imageAlt: image.attributes['alt'] ?? '',
          ),
        );
      }
    }

    void addTable(dom.Element table, List<int> path) {
      final rawRows =
          <List<({String text, int colSpan, int rowSpan, bool header})>>[];
      for (final row in table.querySelectorAll('tr')) {
        if (!_belongsToTable(row, table)) continue;
        final rowIsHeader =
            row.parent?.localName?.toLowerCase() == 'thead' ||
            row.children
                .where((cell) {
                  final tag = cell.localName?.toLowerCase();
                  return tag == 'td' || tag == 'th';
                })
                .every((cell) => cell.localName?.toLowerCase() == 'th');
        final cells = row.children
            .where((cell) {
              final tag = cell.localName?.toLowerCase();
              return tag == 'td' || tag == 'th';
            })
            .map((cell) {
              final tag = cell.localName?.toLowerCase();
              return (
                text: _normaliseText(cell.text),
                colSpan: _span(cell, 'colspan'),
                rowSpan: _span(cell, 'rowspan'),
                header: tag == 'th' || rowIsHeader,
              );
            })
            .toList();
        if (cells.isEmpty) continue;
        rawRows.add(cells);
      }
      if (rawRows.isEmpty) return;
      var headerRows = 0;
      for (final row in rawRows) {
        if (row.every((cell) => cell.header)) {
          headerRows++;
        } else {
          break;
        }
      }
      final rows = <List<EpubTableCell>>[];
      for (var rowIndex = 0; rowIndex < rawRows.length; rowIndex++) {
        rows.add([
          for (final cell in rawRows[rowIndex])
            EpubTableCell(
              text: cell.text,
              colSpan: cell.colSpan,
              rowSpan: cell.rowSpan,
              isHeader: cell.header || rowIndex < headerRows,
            ),
        ]);
      }
      final firstBlock = blocks.length;
      final cfiPath = '/${path.map((step) => (step * 2).toString()).join('/')}';
      blocks.add(
        EpubBlock(
          kind: EpubBlockKind.table,
          text: rows
              .map((row) => row.map((cell) => cell.text).join(' '))
              .join('\n'),
          cfiPath: cfiPath,
          tableRows: rows,
          tableHeaderRows: headerRows,
        ),
      );
      for (final idElement in [table, ...table.querySelectorAll('[id]')]) {
        final id = idElement.attributes['id'];
        if (id != null && id.isNotEmpty) {
          anchors.putIfAbsent(id, () => firstBlock);
        }
      }
    }

    void walk(dom.Element parent, List<int> path) {
      final children = parent.children;
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        final childPath = [...path, i + 1];
        final tag = child.localName?.toLowerCase() ?? '';
        if (tag == 'table') {
          addTable(child, childPath);
        } else if (const {
          'p',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'li',
          'blockquote',
          'pre',
          'code',
          'td',
          'th',
          'figcaption',
        }.contains(tag)) {
          addElement(child, childPath);
        } else if (tag == 'img') {
          final src = child.attributes['src'];
          if (src == null) continue;
          final bytes = files[_normalise(_resolve(chapterDir, src))]
              ?.readBytes();
          if (bytes == null) continue;
          blocks.add(
            EpubBlock(
              kind: EpubBlockKind.image,
              text: '',
              cfiPath:
                  '/${childPath.map((step) => (step * 2).toString()).join('/')}',
              imageBytes: bytes,
              imageAlt: child.attributes['alt'] ?? '',
            ),
          );
        } else if (const {
          'body',
          'div',
          'section',
          'article',
          'main',
          'header',
          'footer',
          'figure',
          'table',
          'thead',
          'tbody',
          'tr',
          'ul',
          'ol',
          'dl',
          'nav',
        }.contains(tag)) {
          final directText = _normaliseText(
            child.nodes
                .whereType<dom.Text>()
                .map((node) => node.text)
                .join(' '),
          );
          if (directText.isNotEmpty) {
            addElement(child, childPath);
          } else {
            walk(child, childPath);
          }
        } else {
          final text = _normaliseText(child.text);
          if (text.isNotEmpty) addElement(child, childPath);
        }
      }
    }

    walk(body, const []);
    return (blocks: blocks, anchors: anchors);
  }

  static ({String text, List<EpubLink> links, List<EpubRuby> rubies})
  _textAndLinks(dom.Element element, String chapterHref) {
    final raw = StringBuffer();
    final rawLinks = <({int start, int end, String target})>[];
    final rawRubies = <({int start, int end, String annotation})>[];
    final chapterDir = p.posix.dirname(chapterHref);

    void visit(dom.Node node, String? href) {
      if (node is dom.Text) {
        if (node.text.isEmpty) return;
        final start = raw.length;
        raw.write(node.text);
        if (href != null) {
          rawLinks.add((start: start, end: raw.length, target: href));
        }
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'script' || tag == 'style' || tag == 'rt' || tag == 'rp') {
        return;
      }
      if (tag == 'ruby') {
        final start = raw.length;
        for (final child in node.nodes) {
          final childTag = child is dom.Element
              ? child.localName?.toLowerCase()
              : null;
          if (childTag == 'rt' || childTag == 'rp') continue;
          visit(child, href);
        }
        final end = raw.length;
        final annotation = _normaliseText(
          node.querySelectorAll('rt').map((element) => element.text).join(' '),
        );
        if (end > start && annotation.isNotEmpty) {
          rawRubies.add((start: start, end: end, annotation: annotation));
        }
        return;
      }
      final target = tag == 'a'
          ? _linkTarget(node.attributes['href'], chapterDir, chapterHref)
          : href;
      for (final child in node.nodes) {
        visit(child, target);
      }
    }

    for (final child in element.nodes) {
      visit(child, null);
    }

    final source = raw.toString();
    final offsets = _normalisedOffsets(source);
    final links = <EpubLink>[];
    for (final link in rawLinks) {
      var start = link.start;
      var end = link.end;
      while (start < end && _isWhitespace(source[start])) {
        start++;
      }
      while (end > start && _isWhitespace(source[end - 1])) {
        end--;
      }
      if (start >= end) continue;
      final normalizedStart = offsets[start];
      final normalizedEnd = offsets[end];
      if (normalizedEnd <= normalizedStart) continue;
      links.add(
        EpubLink(
          start: normalizedStart,
          end: normalizedEnd,
          target: link.target,
        ),
      );
    }
    links.sort((a, b) => a.start.compareTo(b.start));
    final rubies = <EpubRuby>[];
    for (final ruby in rawRubies) {
      var start = ruby.start;
      var end = ruby.end;
      while (start < end && _isWhitespace(source[start])) {
        start++;
      }
      while (end > start && _isWhitespace(source[end - 1])) {
        end--;
      }
      if (start >= end) continue;
      final normalizedStart = offsets[start];
      final normalizedEnd = offsets[end];
      if (normalizedEnd <= normalizedStart) continue;
      rubies.add(
        EpubRuby(
          start: normalizedStart,
          end: normalizedEnd,
          annotation: ruby.annotation,
        ),
      );
    }
    rubies.sort((a, b) => a.start.compareTo(b.start));
    return (text: _normaliseText(source), links: links, rubies: rubies);
  }

  static String? _linkTarget(
    String? href,
    String chapterDir,
    String chapterHref,
  ) {
    final value = href?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('mailto:')) {
      return value;
    }
    final hash = value.indexOf('#');
    final pathPart = hash < 0 ? value : value.substring(0, hash);
    final fragment = hash < 0 ? '' : value.substring(hash);
    final file = pathPart.isEmpty
        ? _normalise(chapterHref)
        : _resolve(chapterDir, pathPart);
    return '$file$fragment';
  }

  static List<int> _normalisedOffsets(String raw) {
    final offsets = List<int>.filled(raw.length + 1, 0);
    final output = StringBuffer();
    var pendingSpace = false;
    for (var i = 0; i < raw.length; i++) {
      offsets[i] = output.length;
      final ch = raw[i];
      if (_isWhitespace(ch)) {
        pendingSpace = true;
        offsets[i + 1] = output.length;
        continue;
      }
      if (pendingSpace && output.isNotEmpty) output.write(' ');
      pendingSpace = false;
      output.write(ch);
      offsets[i + 1] = output.length;
    }
    offsets[raw.length] = output.length;
    return offsets;
  }

  static bool _isWhitespace(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u00a0';

  static List<EpubTocEntry> _parseNav(
    dom.Document document,
    List<EpubChapter> chapters,
    String navHref,
  ) {
    final nav =
        document
            .querySelectorAll('nav')
            .where(
              (element) =>
                  element.attributes['epub:type'] == 'toc' ||
                  element.attributes['role'] == 'doc-toc',
            )
            .firstOrNull ??
        document.querySelector('nav');
    if (nav == null) return const [];
    final navDir = p.posix.dirname(navHref);
    final entries = <EpubTocEntry>[];
    for (final anchor in nav.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null) continue;
      final resolved = _resolve(navDir, href);
      final chapterIndex = _chapterIndexForHref(chapters, resolved);
      if (chapterIndex < 0) continue;
      entries.add(
        EpubTocEntry(
          title: _normaliseText(anchor.text),
          href: resolved,
          chapterIndex: chapterIndex,
        ),
      );
    }
    return entries;
  }

  static List<EpubTocEntry> _parseNcx(
    XmlDocument document,
    List<EpubChapter> chapters,
    String ncxHref,
  ) {
    final ncxDir = p.posix.dirname(ncxHref);
    final entries = <EpubTocEntry>[];
    for (final navPoint in document.findAllElements('navPoint')) {
      final label = navPoint
          .findAllElements('navLabel')
          .firstOrNull
          ?.innerText
          .trim();
      final src = navPoint
          .findAllElements('content')
          .firstOrNull
          ?.getAttribute('src');
      if (src == null || label == null) continue;
      final resolved = _resolve(ncxDir, src);
      final chapterIndex = _chapterIndexForHref(chapters, resolved);
      if (chapterIndex < 0) continue;
      entries.add(
        EpubTocEntry(title: label, href: resolved, chapterIndex: chapterIndex),
      );
    }
    return entries;
  }

  static int _chapterIndexForHref(List<EpubChapter> chapters, String href) {
    final target = _normalise(href.split('#').first);
    return chapters.indexWhere((chapter) => _normalise(chapter.href) == target);
  }

  static String? _firstHeading(List<EpubBlock> blocks) {
    for (final block in blocks) {
      if (block.kind == EpubBlockKind.heading1 ||
          block.kind == EpubBlockKind.heading2 ||
          block.kind == EpubBlockKind.heading3) {
        return block.text;
      }
    }
    return null;
  }

  static String _normaliseText(String value) =>
      value.replaceAll(RegExp(r'[\u00a0\s]+'), ' ').trim();

  static bool _belongsToTable(dom.Element row, dom.Element table) {
    dom.Element? parent = row.parent;
    while (parent != null) {
      if (parent.localName?.toLowerCase() == 'table') {
        return identical(parent, table);
      }
      parent = parent.parent;
    }
    return false;
  }

  static int _span(dom.Element cell, String attribute) {
    final parsed = int.tryParse(cell.attributes[attribute]?.trim() ?? '');
    if (parsed == null) return 1;
    return parsed.clamp(1, 64);
  }

  static ArchiveFile? _findFile(Map<String, ArchiveFile> files, String path) {
    final normalised = _normalise(path);
    return files[normalised] ??
        files.entries
            .where(
              (entry) => entry.key.toLowerCase() == normalised.toLowerCase(),
            )
            .firstOrNull
            ?.value;
  }

  static String _resolve(String baseDir, String href) {
    final withoutFragment = href.split('#').first;
    final decoded = Uri.decodeComponent(withoutFragment);
    return _normalise(p.posix.join(baseDir, decoded));
  }

  static String _normalise(String path) {
    var value = path.replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    return p.posix.normalize(value);
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String href;
  final String mediaType;
  final String properties;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
