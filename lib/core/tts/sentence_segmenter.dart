/// Sentence-level TTS cadence shared by PDF, EPUB and DOCX readers.
///
/// Phase 0 deliberately targets reliable *sentence* boundaries, not word-level
/// timestamps. The original character offsets are preserved so the UI can map a
/// spoken sentence back to a document anchor without re-tokenising the text.
class SentenceSpan {
  const SentenceSpan({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;

  @override
  String toString() => 'SentenceSpan($start..$end, "$text")';
}

class SentenceSegmenter {
  const SentenceSegmenter._();

  static const _closingMarks = '”’"\u300d\u300f\u3011\u3009\u300b）)】]' ;
  static const _hardStops = '。！？!?；;…';
  static const _softStops = ',，、：:';
  static const maxSentenceLength = 260;

  /// Splits [text] into non-empty, ordered spans. Offsets are UTF-16 code-unit
  /// offsets into [text], matching Dart's `String.substring`.
  static List<SentenceSpan> split(String text) {
    if (text.trim().isEmpty) return const [];

    final spans = <SentenceSpan>[];
    var sentenceStart = 0;

    void emit(int endExclusive) {
      var start = sentenceStart;
      var end = endExclusive.clamp(0, text.length);
      while (start < end && _isTrimChar(text.codeUnitAt(start))) {
        start++;
      }
      while (end > start && _isTrimChar(text.codeUnitAt(end - 1))) {
        end--;
      }
      if (end > start) {
        spans.add(SentenceSpan(
          start: start,
          end: end,
          text: text.substring(start, end),
        ));
      }
      sentenceStart = endExclusive;
    }

    var i = 0;
    while (i < text.length) {
      final char = text[i];
      var boundary = false;

      if (char == '\n' || char == '\r') {
        boundary = true;
      } else if (_hardStops.contains(char)) {
        boundary = true;
        // Keep a closing quote/bracket with the sentence it closes.
        var cursor = i + 1;
        while (cursor < text.length && _closingMarks.contains(text[cursor])) {
          cursor++;
        }
        i = cursor - 1;
      } else if (char == '.') {
        final next = i + 1 < text.length ? text[i + 1] : '';
        final previous = i > 0 ? text[i - 1] : '';
        final isDecimal = RegExp(r'\d').hasMatch(previous) &&
            RegExp(r'\d').hasMatch(next);
        boundary = !isDecimal && (next.isEmpty || _isWhitespace(next));
      }

      if (boundary) {
        emit(i + 1);
      } else if (i - sentenceStart + 1 >= maxSentenceLength) {
        // Long paragraphs without punctuation still need bounded TTS chunks.
        // Prefer a natural soft stop, otherwise cut at the hard limit.
        final window = text.substring(sentenceStart, i + 1);
        var cut = -1;
        for (final stop in _softStops.split('')) {
          final index = window.lastIndexOf(stop);
          if (index > cut) cut = index;
        }
        if (cut < 40) {
          cut = i - sentenceStart;
        }
        emit(sentenceStart + cut + 1);
      }
      i++;
    }
    emit(text.length);

    return spans;
  }

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';

  static bool _isTrimChar(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D ||
        codeUnit == 0x3000;
  }
}
