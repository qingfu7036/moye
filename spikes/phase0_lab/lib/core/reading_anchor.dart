import 'dart:math' as math;

enum BookFormat { pdf, epub, docx, txt, markdown }

/// A page-space rectangle as returned by PDFium. PDF coordinates have their
/// origin at the bottom-left and `top` is numerically larger than `bottom`.
class PdfRectData {
  const PdfRectData(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, Object?> toJson() => {
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };

  factory PdfRectData.fromJson(Map<String, Object?> json) => PdfRectData(
        (json['left'] as num).toDouble(),
        (json['top'] as num).toDouble(),
        (json['right'] as num).toDouble(),
        (json['bottom'] as num).toDouble(),
      );

  @override
  String toString() =>
      'PdfRectData(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, '
      '${right.toStringAsFixed(2)}, ${bottom.toStringAsFixed(2)})';
}

/// Format-neutral persistent anchor.
///
/// A quote alone is never sufficient: every anchor also carries structural
/// coordinates plus surrounding context. The context lets a later version
/// re-anchor safely after a font change or a replaced source file.
class ReadingAnchor {
  const ReadingAnchor({
    required this.format,
    required this.quote,
    this.page,
    this.pageStart,
    this.pageEnd,
    this.spineIndex,
    this.blockIndex,
    this.charOffset,
    this.cfi,
    this.docxPath,
    this.contextBefore = '',
    this.contextAfter = '',
    this.pdfRects = const [],
    this.textHash,
    this.color,
  });

  final BookFormat format;
  final String quote;
  final int? page;
  final int? pageStart;
  final int? pageEnd;
  final int? spineIndex;
  final int? blockIndex;
  final int? charOffset;
  final String? cfi;
  final String? docxPath;
  final String contextBefore;
  final String contextAfter;
  final List<PdfRectData> pdfRects;
  final String? textHash;
  final String? color;

  Map<String, Object?> toJson() => {
        'format': format.name,
        'quote': quote,
        if (page != null) 'page': page,
        if (pageStart != null) 'pageStart': pageStart,
        if (pageEnd != null) 'pageEnd': pageEnd,
        if (spineIndex != null) 'spineIndex': spineIndex,
        if (blockIndex != null) 'blockIndex': blockIndex,
        if (charOffset != null) 'charOffset': charOffset,
        if (cfi != null) 'cfi': cfi,
        if (docxPath != null) 'docxPath': docxPath,
        'contextBefore': contextBefore,
        'contextAfter': contextAfter,
        if (pdfRects.isNotEmpty)
          'pdfRects': pdfRects.map((rect) => rect.toJson()).toList(),
        if (textHash != null) 'textHash': textHash,
        if (color != null) 'color': color,
      };

  factory ReadingAnchor.fromJson(Map<String, Object?> json) {
    final formatName = json['format'] as String? ?? 'txt';
    final format = BookFormat.values.firstWhere(
      (value) => value.name == formatName,
      orElse: () => BookFormat.txt,
    );
    final rawRects = json['pdfRects'] as List<Object?>? ?? const [];
    return ReadingAnchor(
      format: format,
      quote: json['quote'] as String? ?? '',
      page: (json['page'] as num?)?.toInt(),
      pageStart: (json['pageStart'] as num?)?.toInt(),
      pageEnd: (json['pageEnd'] as num?)?.toInt(),
      spineIndex: (json['spineIndex'] as num?)?.toInt(),
      blockIndex: (json['blockIndex'] as num?)?.toInt(),
      charOffset: (json['charOffset'] as num?)?.toInt(),
      cfi: json['cfi'] as String?,
      docxPath: json['docxPath'] as String?,
      contextBefore: json['contextBefore'] as String? ?? '',
      contextAfter: json['contextAfter'] as String? ?? '',
      pdfRects: rawRects
          .whereType<Map>()
          .map((raw) => PdfRectData.fromJson(
                raw.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList(),
      textHash: json['textHash'] as String?,
      color: json['color'] as String?,
    );
  }

  ReadingAnchor copyWith({
    String? quote,
    int? page,
    int? pageStart,
    int? pageEnd,
    int? charOffset,
    String? cfi,
    String? contextBefore,
    String? contextAfter,
    List<PdfRectData>? pdfRects,
    String? textHash,
    String? color,
  }) {
    return ReadingAnchor(
      format: format,
      quote: quote ?? this.quote,
      page: page ?? this.page,
      pageStart: pageStart ?? this.pageStart,
      pageEnd: pageEnd ?? this.pageEnd,
      spineIndex: spineIndex,
      blockIndex: blockIndex,
      charOffset: charOffset ?? this.charOffset,
      cfi: cfi ?? this.cfi,
      docxPath: docxPath,
      contextBefore: contextBefore ?? this.contextBefore,
      contextAfter: contextAfter ?? this.contextAfter,
      pdfRects: pdfRects ?? this.pdfRects,
      textHash: textHash ?? this.textHash,
      color: color ?? this.color,
    );
  }
}

class ReanchorResult {
  const ReanchorResult({
    required this.start,
    required this.end,
    required this.confidence,
    required this.exactQuoteMatch,
  });

  final int start;
  final int end;
  final double confidence;
  final bool exactQuoteMatch;

  bool get isReliable => confidence >= 0.6;
}

/// Re-locates a quote using context. This is intentionally conservative: an
/// ambiguous quote is not silently mapped to the first occurrence.
class Anchoring {
  const Anchoring._();

  static ReanchorResult? find(
    String documentText,
    ReadingAnchor anchor, {
    int contextRadius = 48,
  }) {
    final quote = anchor.quote;
    if (quote.isEmpty) return null;

    final offsets = <int>[];
    var from = 0;
    while (true) {
      final found = documentText.indexOf(quote, from);
      if (found < 0) break;
      offsets.add(found);
      from = found + math.max(1, quote.length);
    }
    if (offsets.isEmpty) return null;

    final expectedBefore = anchor.contextBefore;
    final expectedAfter = anchor.contextAfter;
    var bestOffset = offsets.first;
    var bestScore = -1.0;

    for (final offset in offsets) {
      final actualBefore = documentText.substring(
        math.max(0, offset - contextRadius),
        offset,
      );
      final actualAfter = documentText.substring(
        offset + quote.length,
        math.min(documentText.length, offset + quote.length + contextRadius),
      );
      final beforeScore = _suffixScore(expectedBefore, actualBefore);
      final afterScore = _prefixScore(expectedAfter, actualAfter);
      final structuralBonus = anchor.charOffset == null
          ? 0.0
          : 1.0 - ((offset - anchor.charOffset!).abs() / 10000).clamp(0.0, 0.5);
      final score = beforeScore * 0.35 + afterScore * 0.45 + structuralBonus * 0.2;
      if (score > bestScore) {
        bestScore = score;
        bestOffset = offset;
      }
    }

    final exact = offsets.length == 1 && bestScore >= 0.6;
    return ReanchorResult(
      start: bestOffset,
      end: bestOffset + quote.length,
      confidence: bestScore.clamp(0.0, 1.0),
      exactQuoteMatch: exact,
    );
  }

  static double _suffixScore(String expected, String actual) {
    if (expected.isEmpty || actual.isEmpty) return 0.0;
    var score = 0;
    final max = math.min(expected.length, actual.length);
    for (var i = 0; i < max; i++) {
      if (expected.codeUnitAt(expected.length - 1 - i) !=
          actual.codeUnitAt(actual.length - 1 - i)) {
        break;
      }
      score++;
    }
    return score / expected.length;
  }

  static double _prefixScore(String expected, String actual) {
    if (expected.isEmpty || actual.isEmpty) return 0.0;
    var score = 0;
    final max = math.min(expected.length, actual.length);
    for (var i = 0; i < max; i++) {
      if (expected.codeUnitAt(i) != actual.codeUnitAt(i)) break;
      score++;
    }
    return score / expected.length;
  }

  /// Stable FNV-1a hash used to detect a changed source document.
  static String textHash(String text) {
    var hash = 0x811c9dc5;
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
