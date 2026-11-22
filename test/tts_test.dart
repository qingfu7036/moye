import 'package:flutter_test/flutter_test.dart';
import 'package:moye/core/tts/sentence_segmenter.dart';

void main() {
  test('splits Chinese and English sentences while preserving offsets', () {
    const text = '第一句。Second sentence! 第三句？';
    final spans = SentenceSegmenter.split(text);
    expect(spans.map((span) => span.text), [
      '第一句。',
      'Second sentence!',
      '第三句？',
    ]);
    for (final span in spans) {
      expect(text.substring(span.start, span.end), span.text);
    }
  });

  test('does not split decimal numbers and bounds very long text', () {
    final decimal = SentenceSegmenter.split('版本 1.0 很好。');
    expect(decimal.map((span) => span.text), ['版本 1.0 很好。']);

    final long = SentenceSegmenter.split('甲' * 600);
    expect(long, isNotEmpty);
    expect(long.every((span) => span.text.length <= 260), isTrue);
  });
}
