import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 영어 문장 읽어주기
abstract class Speaker {
  /// [slow] 이면 0.8배 속도로 읽는다.
  Future<void> speak(String text, {bool slow = false});
  Future<void> stop();
  void configure({required String voice, required double speed});
}

class DeviceSpeaker implements Speaker {
  final _tts = FlutterTts();
  String _voice = 'en-US';
  double _speed = 1.0;
  bool _ready = false;

  @override
  void configure({required String voice, required double speed}) {
    if (voice != _voice) _ready = false;
    _voice = voice;
    _speed = speed;
  }

  /// 플랫폼마다 "보통 속도" 값이 다르다 (모바일 0.5, 웹 1.0).
  double _rate(bool slow) {
    final base = kIsWeb ? 1.0 : 0.5;
    return base * _speed * (slow ? 0.8 : 1.0);
  }

  @override
  Future<void> speak(String text, {bool slow = false}) async {
    try {
      if (!_ready) {
        await _tts.setLanguage(_voice);
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      await _tts.stop();
      await _tts.setSpeechRate(_rate(slow));
      await _tts.speak(text);
    } catch (_) {
      // 음성 엔진이 없는 기기에서도 학습은 계속할 수 있게 조용히 넘어간다.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final speakerProvider = Provider<Speaker>((ref) => DeviceSpeaker());
