import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:moye/core/tts/tts_service.dart';

class _FakeTts extends FlutterTts {
  final List<String> spoken = [];
  VoidCallback? completion;

  @override
  Future<dynamic> awaitSpeakCompletion(bool value) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;

  @override
  Future<dynamic> pause() async => 1;

  @override
  Future<dynamic> get getVoices async => <Map<String, Object?>>[];

  @override
  void setCompletionHandler(VoidCallback callback) {
    completion = callback;
  }

  @override
  void setCancelHandler(VoidCallback callback) {}

  @override
  void setErrorHandler(ErrorHandler handler) {}

  void complete() => completion?.call();
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('speaks one sentence at a time and advances on completion', () async {
    final fake = _FakeTts();
    final service = TtsService(engine: fake);
    await service.initialize();
    await service.loadSegments([const TtsSegment(text: '第一句。第二句。')]);
    await service.play();
    expect(fake.spoken, ['第一句。']);

    fake.complete();
    await _settle();
    expect(fake.spoken, ['第一句。', '第二句。']);
    expect(service.currentSentence?.text, '第二句。');

    fake.complete();
    await _settle();
    expect(service.state, TtsPlaybackState.idle);
  });

  test('loads the next segment when the current queue is finished', () async {
    final fake = _FakeTts();
    final service = TtsService(engine: fake);
    await service.initialize();
    await service.loadSegments(
      [const TtsSegment(text: '第一页。')],
      nextSegmentLoader: () async =>
          const TtsSegment(text: '第二页。', pageNumber: 2),
    );
    await service.play();
    fake.complete();
    await _settle();
    expect(fake.spoken, ['第一页。', '第二页。']);
    expect(service.currentSegment?.pageNumber, 2);
  });
}
