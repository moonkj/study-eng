import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 음성 인식 결과
class SpeechAttempt {
  const SpeechAttempt.heard(String this.text) : error = null;
  const SpeechAttempt.failed(String this.error) : text = null;

  final String? text;

  /// 사용자에게 보여줄 실패 이유
  final String? error;

  bool get ok => text != null && text!.trim().isNotEmpty;
}

/// 따라 말하기 입력
abstract class SpeechInput {
  /// 사용자가 [expected] 문장을 말하는 동안 [onPartial] 로 중간 결과를 알리고, 끝나면 결과를 돌려준다.
  /// [expected] 는 인식 힌트로도 쓰인다 (iOS contextual phrases).
  Future<SpeechAttempt> listen({required String expected, void Function(String partial)? onPartial});

  /// 말하기를 끝낸다 (버튼을 한 번 더 누를 때).
  Future<void> stop();
}

/// 기기 음성 인식 (Android: Google 음성 인식, iOS: Speech framework, 웹: Chrome)
class DeviceSpeechInput implements SpeechInput {
  final _stt = SpeechToText();
  bool? _available;
  String? _initError;
  Completer<SpeechAttempt>? _pending;

  Future<bool> _ensure() async {
    if (_available == true) return true;
    try {
      _available = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    } catch (e) {
      _available = false;
      _initError = '$e';
    }
    return _available!;
  }

  void _onError(dynamic e) {
    final msg = '${e.errorMsg}';
    final friendly = switch (msg) {
      'error_no_match' || 'error_speech_timeout' => '잘 들리지 않았어요. 조금 더 크게 말해 볼까요?',
      'error_permission' || 'error_insufficient_permissions' => '마이크 권한이 필요해요. 설정에서 허용해 주세요.',
      'error_network' || 'error_network_timeout' => '음성 인식에 인터넷 연결이 필요해요.',
      _ => '음성 인식 중 문제가 생겼어요. ($msg)',
    };
    _finish(SpeechAttempt.failed(friendly));
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // 최종 결과 콜백보다 상태 변경이 먼저 올 수 있어 잠깐 기다린다.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        final words = _stt.lastRecognizedWords;
        _finish(words.isEmpty ? const SpeechAttempt.failed('잘 들리지 않았어요. 다시 말해 볼까요?') : SpeechAttempt.heard(words));
      });
    }
  }

  void _finish(SpeechAttempt a) {
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete(a);
  }

  @override
  Future<SpeechAttempt> listen({required String expected, void Function(String partial)? onPartial}) async {
    if (!await _ensure()) {
      return SpeechAttempt.failed(
        _initError == null ? '이 기기에서는 음성 인식을 쓸 수 없어요. 마이크 권한을 확인해 주세요.' : '음성 인식을 시작하지 못했어요.',
      );
    }
    final pending = _pending = Completer<SpeechAttempt>();
    await _stt.listen(
      onResult: (r) {
        onPartial?.call(r.recognizedWords);
        if (r.finalResult) _finish(SpeechAttempt.heard(r.recognizedWords));
      },
      listenOptions: SpeechListenOptions(
        localeId: 'en_US',
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        contextualPhrases: [expected],
      ),
    );
    return pending.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => _stt.lastRecognizedWords.isEmpty
          ? const SpeechAttempt.failed('잘 들리지 않았어요. 다시 말해 볼까요?')
          : SpeechAttempt.heard(_stt.lastRecognizedWords),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}

final speechInputProvider = Provider<SpeechInput>((ref) => DeviceSpeechInput());
