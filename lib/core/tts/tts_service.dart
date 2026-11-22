import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'sentence_segmenter.dart';

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

/// A source chunk that can be mapped back to a reader location.
class TtsSegment {
  const TtsSegment({
    required this.text,
    this.pageNumber,
    this.chapterIndex,
    this.blockIndex,
  });

  final String text;
  final int? pageNumber;
  final int? chapterIndex;
  final int? blockIndex;
}

class TtsSentence {
  const TtsSentence({
    required this.text,
    required this.start,
    required this.end,
    required this.segmentIndex,
  });

  final String text;
  final int start;
  final int end;
  final int segmentIndex;
}

/// Sentence-level system TTS.
///
/// One sentence is submitted per utterance; the engine's completion callback
/// advances the queue. This deliberately avoids word-boundary timestamps that
/// are not consistently available on Windows and Android.
class TtsService extends ChangeNotifier {
  TtsService({FlutterTts? engine}) : _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  final List<TtsVoice> voices = [];
  List<TtsSegment> _segments = const [];
  List<TtsSentence> _sentences = const [];
  Future<TtsSegment?> Function()? _nextSegmentLoader;

  TtsPlaybackState state = TtsPlaybackState.idle;
  TtsVoice? selectedVoice;
  double rate = 0.5;
  String? error;
  int _index = -1;
  int _runToken = 0;
  bool _initialized = false;
  bool _completionBusy = false;

  bool get initialized => _initialized;
  int get currentIndex => _index;
  TtsSentence? get currentSentence =>
      _index >= 0 && _index < _sentences.length ? _sentences[_index] : null;
  TtsSegment? get currentSegment {
    final sentence = currentSentence;
    if (sentence == null ||
        sentence.segmentIndex < 0 ||
        sentence.segmentIndex >= _segments.length) {
      return null;
    }
    return _segments[sentence.segmentIndex];
  }

  int get sentenceCount => _sentences.length;
  bool get hasText => _sentences.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(0.6);
      _tts.setCompletionHandler(() {
        unawaited(_onUtteranceComplete());
      });
      _tts.setCancelHandler(() {
        if (state == TtsPlaybackState.playing) {
          state = TtsPlaybackState.idle;
          notifyListeners();
        }
      });
      _tts.setErrorHandler((message) {
        error = message.toString();
        state = TtsPlaybackState.idle;
        _index = -1;
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
          voices.add(
            TtsVoice(
              name: name,
              locale: locale,
              gender: (map['gender'] ?? '').toString(),
              identifier: identifier,
              raw: map.cast<String, dynamic>(),
            ),
          );
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
      error = null;
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<void> loadSegments(
    List<TtsSegment> segments, {
    Future<TtsSegment?> Function()? nextSegmentLoader,
  }) async {
    await _tts.stop();
    _runToken++;
    _segments = [...segments];
    _nextSegmentLoader = nextSegmentLoader;
    _sentences = _flatten();
    _index = -1;
    _completionBusy = false;
    state = TtsPlaybackState.idle;
    error = null;
    notifyListeners();
  }

  Future<void> selectVoice(TtsVoice voice) async {
    selectedVoice = voice;
    try {
      await _tts.setVoice(voice.platformMap);
      error = null;
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    rate = value.clamp(0.25, 0.75).toDouble();
    try {
      await _tts.setSpeechRate(rate);
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<void> play({int? from}) async {
    if (!_initialized) await initialize();
    if (!hasText) return;
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
    try {
      await _tts.pause();
    } catch (exception) {
      // Some Android engines cannot pause before API 26. Stopping is safer
      // than leaving the UI in a false playing state.
      error = exception.toString();
      await stop();
    }
  }

  Future<void> resume() async {
    if (state != TtsPlaybackState.paused) return;
    if (currentSentence == null) {
      state = TtsPlaybackState.idle;
      notifyListeners();
      return;
    }
    state = TtsPlaybackState.playing;
    notifyListeners();
    final result = await _tts.speak(currentSentence!.text);
    if (result != 1) _rejectPlayback(result);
  }

  Future<void> stop() async {
    _runToken++;
    _completionBusy = false;
    state = TtsPlaybackState.idle;
    _index = -1;
    notifyListeners();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _sentences.length) return;
    final wasPlaying = state == TtsPlaybackState.playing;
    await _tts.stop();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    _index = index;
    if (wasPlaying) {
      state = TtsPlaybackState.playing;
      notifyListeners();
      await _speakCurrent();
    } else {
      state = TtsPlaybackState.idle;
      notifyListeners();
    }
  }

  List<TtsSentence> _flatten() {
    final result = <TtsSentence>[];
    for (var segmentIndex = 0; segmentIndex < _segments.length; segmentIndex++) {
      final spans = SentenceSegmenter.split(_segments[segmentIndex].text);
      for (final span in spans) {
        result.add(
          TtsSentence(
            text: span.text,
            start: span.start,
            end: span.end,
            segmentIndex: segmentIndex,
          ),
        );
      }
    }
    return result;
  }

  bool _appendSegment(TtsSegment segment) {
    final before = _sentences.length;
    _segments = [..._segments, segment];
    final spans = SentenceSegmenter.split(segment.text);
    final segmentIndex = _segments.length - 1;
    for (final span in spans) {
      _sentences = [
        ..._sentences,
        TtsSentence(
          text: span.text,
          start: span.start,
          end: span.end,
          segmentIndex: segmentIndex,
        ),
      ];
    }
    return _sentences.length > before;
  }

  Future<void> _speakCurrent() async {
    if (state != TtsPlaybackState.playing) return;
    if (_index < 0 || _index >= _sentences.length) {
      await _finishOrLoadNext();
      return;
    }
    final token = ++_runToken;
    notifyListeners();
    final result = await _tts.speak(_sentences[_index].text);
    if (token != _runToken) return;
    if (result != 1) _rejectPlayback(result);
  }

  Future<void> _onUtteranceComplete() async {
    if (_completionBusy || state != TtsPlaybackState.playing) return;
    _completionBusy = true;
    try {
      if (_index + 1 < _sentences.length) {
        _index++;
        await _speakCurrent();
        return;
      }
      await _finishOrLoadNext();
    } finally {
      _completionBusy = false;
    }
  }

  Future<void> _finishOrLoadNext() async {
    final loader = _nextSegmentLoader;
    if (loader != null) {
      while (state == TtsPlaybackState.playing) {
        final next = await loader();
        if (next == null) break;
        if (_appendSegment(next)) {
          _index = _sentences.length - 1 -
              SentenceSegmenter.split(next.text).length +
              1;
          if (_index < 0) _index = 0;
          await _speakCurrent();
          return;
        }
      }
    }
    state = TtsPlaybackState.idle;
    _index = -1;
    notifyListeners();
  }

  void _rejectPlayback(Object? result) {
    error = '系统 TTS 拒绝播放：$result';
    state = TtsPlaybackState.idle;
    _index = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
