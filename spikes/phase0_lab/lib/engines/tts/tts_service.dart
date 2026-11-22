import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/sentence_segmenter.dart';

enum TtsPlaybackState { idle, playing, paused }

class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    required this.gender,
    required this.identifier,
    required this.raw,
  });

  final String name;
  final String locale;
  final String gender;
  final String identifier;
  final Map<String, dynamic> raw;

  bool get isChinese => locale.toLowerCase().startsWith('zh');

  String get label => '$name · $locale';

  Map<String, String> get platformMap =>
      raw.map((key, value) => MapEntry(key, value.toString()));
}

/// Thin adapter around the platform TTS engine.
///
/// The V1 speech system can replace [FlutterTts] behind this interface without
/// touching reader widgets. Phase 0 speaks one sentence per utterance, so
/// sentence highlighting does not depend on word-boundary callbacks that some
/// Windows/Android engines do not provide.
class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<int> activeSentence = ValueNotifier(-1);

  final List<TtsVoice> voices = [];
  final List<String> logs = [];
  List<SentenceSpan> _sentences = const [];
  int _index = -1;
  bool _initialized = false;
  int _runToken = 0;

  TtsPlaybackState state = TtsPlaybackState.idle;
  String? error;
  TtsVoice? selectedVoice;
  double rate = 0.5;

  bool get initialized => _initialized;
  List<SentenceSpan> get sentences => _sentences;
  int get currentIndex => _index;
  SentenceSpan? get currentSentence =>
      _index >= 0 && _index < _sentences.length ? _sentences[_index] : null;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(0.6);
      _tts.setStartHandler(() => _log('start'));
      _tts.setCompletionHandler(_onUtteranceComplete);
      _tts.setCancelHandler(() => _log('cancel'));
      _tts.setPauseHandler(() => _log('pause'));
      _tts.setContinueHandler(() => _log('continue'));
      _tts.setErrorHandler((message) {
        error = message.toString();
        state = TtsPlaybackState.idle;
        _index = -1;
        activeSentence.value = -1;
        _log('error: $error');
        notifyListeners();
      });

      final rawVoices = await _tts.getVoices;
      if (rawVoices is List) {
        for (final raw in rawVoices) {
          if (raw is! Map) continue;
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          final locale = (map['locale'] ?? map['language'] ?? '').toString();
          final name = (map['name'] ?? 'System voice').toString();
          final identifier =
              (map['identifier'] ?? map['name'] ?? locale).toString();
          voices.add(TtsVoice(
            name: name,
            locale: locale,
            gender: (map['gender'] ?? '').toString(),
            identifier: identifier,
            raw: map.cast<String, dynamic>(),
          ));
        }
      }
      voices.sort((a, b) {
        final byLocale = a.locale.compareTo(b.locale);
        return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
      });
      if (voices.isNotEmpty) {
        selectedVoice = voices.firstWhere(
          (voice) => voice.isChinese,
          orElse: () => voices.first,
        );
        await _tts.setVoice(selectedVoice!.platformMap);
      }
      _initialized = true;
      _log('engine ready · ${voices.length} voices');
    } catch (exception) {
      error = exception.toString();
      _log('init failed: $error');
    }
    notifyListeners();
  }

  Future<void> loadText(String text) async {
    await _tts.stop();
    _runToken++;
    _sentences = SentenceSegmenter.split(text);
    _index = -1;
    activeSentence.value = -1;
    state = TtsPlaybackState.idle;
    notifyListeners();
  }

  Future<void> selectVoice(TtsVoice voice) async {
    selectedVoice = voice;
    await _tts.setVoice(voice.platformMap);
    _log('voice: ${voice.label}');
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    rate = value.clamp(0.25, 0.75).toDouble();
    await _tts.setSpeechRate(rate);
    notifyListeners();
  }

  Future<void> play({int? from}) async {
    if (!_initialized || _sentences.isEmpty) return;
    if (state == TtsPlaybackState.paused) {
      return resume();
    }
    if (from != null) _index = from;
    if (_index < 0 || _index >= _sentences.length) _index = 0;
    error = null;
    state = TtsPlaybackState.playing;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> pause() async {
    if (state != TtsPlaybackState.playing) return;
    state = TtsPlaybackState.paused;
    notifyListeners();
    await _tts.pause();
  }

  Future<void> resume() async {
    if (state != TtsPlaybackState.paused) return;
    state = TtsPlaybackState.playing;
    notifyListeners();
    final result = await _tts.speak(currentSentence?.text ?? '');
    if (result != 1) {
      _rejectPlayback(result);
      return;
    }
    _log('resume current sentence');
  }

  Future<void> stop() async {
    if (state == TtsPlaybackState.idle) return;
    _runToken++;
    state = TtsPlaybackState.idle;
    _index = -1;
    activeSentence.value = -1;
    notifyListeners();
    await _tts.stop();
    _log('stop');
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _sentences.length) return;
    final wasPlaying = state == TtsPlaybackState.playing;
    await _tts.stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _index = index;
    activeSentence.value = index;
    if (wasPlaying) {
      state = TtsPlaybackState.playing;
      notifyListeners();
      await _speakCurrent();
    } else {
      state = TtsPlaybackState.idle;
      notifyListeners();
    }
  }

  Future<void> _speakCurrent() async {
    if (state != TtsPlaybackState.playing) return;
    if (_index < 0 || _index >= _sentences.length) {
      state = TtsPlaybackState.idle;
      activeSentence.value = -1;
      notifyListeners();
      return;
    }
    final token = ++_runToken;
    activeSentence.value = _index;
    _log('speak #${_index + 1}: ${_sentences[_index].text}');
    notifyListeners();
    final result = await _tts.speak(_sentences[_index].text);
    if (token != _runToken) return;
    if (result != 1) {
      _rejectPlayback(result);
    }
  }

  void _rejectPlayback(Object? result) {
    error = '系统 TTS 拒绝播放：$result';
    state = TtsPlaybackState.idle;
    _index = -1;
    activeSentence.value = -1;
    _log('speak rejected: $result');
    notifyListeners();
  }

  void _onUtteranceComplete() {
    _log('complete #${_index + 1}');
    if (state != TtsPlaybackState.playing) return;
    if (_index + 1 >= _sentences.length) {
      state = TtsPlaybackState.idle;
      _index = -1;
      activeSentence.value = -1;
      notifyListeners();
      return;
    }
    _index++;
    _speakCurrent();
  }

  void _log(String message) {
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    logs.insert(0, '$stamp  $message');
    if (logs.length > 60) logs.removeLast();
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    activeSentence.dispose();
    super.dispose();
  }
}
