import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moye_phase0/engines/tts/tts_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows system TTS exposes voices, callbacks and pause/resume',
      (tester) async {
    await tester.runAsync(() async {
      final service = TtsService();
      await service.initialize();
      // ignore: avoid_print
      print('TTS_INITIALIZED=${service.initialized}');
      // ignore: avoid_print
      print('TTS_ERROR=${service.error}');
      // ignore: avoid_print
      print('TTS_VOICES=${service.voices.length}');
      for (final voice in service.voices.take(12)) {
        // ignore: avoid_print
        print('TTS_VOICE=${voice.name}|${voice.locale}|${voice.gender}');
      }
      expect(service.voices, isNotEmpty);
      expect(service.selectedVoice, isNotNull);

      await service.loadText(
        '这是墨页语音同步验证的第一句。'
        '暂停和继续需要在句子中间发生，才能证明播放状态没有丢失。'
        '最后一句用于确认自动推进和结束回调。',
      );
      expect(service.sentences.length, 3);

      await service.play();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await service.pause();
      expect(service.state, TtsPlaybackState.paused);
      final pausedAt = service.currentIndex;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(service.state, TtsPlaybackState.paused);
      expect(service.currentIndex, pausedAt);
      await service.resume();

      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        if (service.logs.any((line) => line.contains('complete #3'))) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        service.logs.any((line) => line.contains('complete #3')),
        isTrue,
        reason: 'The third sentence did not complete. Logs: ${service.logs}',
      );
      // ignore: avoid_print
      print('TTS_LOGS_BEGIN');
      for (final line in service.logs.reversed) {
        // ignore: avoid_print
        print(line);
      }
      // ignore: avoid_print
      print('TTS_LOGS_END');
      await service.stop();
      service.dispose();
    });
  });
}
