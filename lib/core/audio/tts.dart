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

/// 마이크(음성 인식·녹음)나 다른 재생이 iOS 오디오 설정을 바꿨음을 알린다. 다음 읽어 주기 때 일반 재생 설정으로 되돌린다.
void markAudioSessionChanged() => DeviceSpeaker._sessionReady = false;

class DeviceSpeaker implements Speaker {
  /// iOS 오디오 설정을 일반 재생으로 맞춰 둔 상태인지. 누를 때마다 설정을 다시 적용하면
  /// 소리가 작게 시작했다 커져서, 단어처럼 짧은 소리는 작게 들린다.
  static bool _sessionReady = false;

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
      // iOS: 기본 오디오 설정은 무음 모드(벨 스위치)에서 소리가 나지 않는다. 사용자가 직접 누른 듣기이므로 playback 으로 바꿔
      // 무음 모드에서도 들리게 한다. playAndRecord(마이크용) 설정에서는 통화용 음량 처리로 소리가 작아지므로
      // 말하기 연습 중 마이크가 바꾼 설정·모드도 매번 일반 재생으로 되돌린다.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !_sessionReady) {
        await _tts.setSharedInstance(true);
        // 읽기가 끝날 때 오디오를 끄지 않는다 (끄면 바로 이어 재생하는 내 녹음이 소리 없이 지나간다)
        await _tts.autoStopSharedSession(false);
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ], IosTextToSpeechAudioMode.defaultMode);
        _sessionReady = true;
      }
      if (!_ready) {
        await _tts.setLanguage(_voice);
        await _tts.awaitSpeakCompletion(true);
        await _tts.setVolume(1.0);
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
