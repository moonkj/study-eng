import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
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
      // iOS: 기본 오디오 설정은 무음 모드(벨 스위치)에서 소리가 나지 않는다.
      // 사용자가 직접 누른 듣기이므로 무음 모드에서도 스피커로 들리게 한다. 말하기 연습 중 마이크가 바꾼 설정도 매번 되돌린다.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ]);
      }
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
