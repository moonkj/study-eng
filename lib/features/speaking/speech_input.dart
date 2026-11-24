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

/// 기기 음성 인식 엔진 (speech_to_text 를 감싼다. 테스트에서 가짜로 바꿀 수 있게)
abstract class SttEngine {
  Future<bool> initialize({
    required void Function(String errorMsg) onError,
    required void Function(String status) onStatus,
  });
  Future<void> listen({required String expected, required void Function(String words, bool isFinal) onResult});
  Future<void> stop();
  Future<void> cancel();
  bool get isListening;
}

class _PluginEngine implements SttEngine {
  final _stt = SpeechToText();

  @override
  Future<bool> initialize({required void Function(String) onError, required void Function(String) onStatus}) =>
      _stt.initialize(onError: (e) => onError(e.errorMsg), onStatus: onStatus);

  @override
  Future<void> listen({required String expected, required void Function(String, bool) onResult}) async {
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
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
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();

  @override
  bool get isListening => _stt.isListening;
}

/// 기기 음성 인식 (Android: Google 음성 인식, iOS: Speech framework, 웹: Chrome)
///
/// 같은 문장을 여러 번 다시 말할 수 있어야 하므로, 시도마다 번호를 붙이고
/// 이전 시도에서 늦게 도착한 상태·오류·결과 알림은 무시한다.
/// (예전에는 첫 시도의 '끝남' 알림이 두 번째 시도를 시작하자마자 첫 결과로 끝내 버려 다시 말하기가 되지 않았다)
class DeviceSpeechInput implements SpeechInput {
  DeviceSpeechInput({SttEngine? engine}) : _stt = engine ?? _PluginEngine();

  final SttEngine _stt;
  bool? _available;
  String? _initError;
  Completer<SpeechAttempt>? _pending;

  /// 지금 시도의 번호와 상태
  int _attempt = 0;
  bool _started = false;
  String _words = '';

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

  static bool _isPermission(String msg) => msg == 'error_permission' || msg == 'error_insufficient_permissions';

  void _onError(String msg) {
    // 듣기를 시작하기 전에 온 '안 들림' 오류는 이전 시도의 것이다
    if (!_started && !_isPermission(msg)) return;
    final friendly = switch (msg) {
      'error_no_match' || 'error_speech_timeout' => '잘 들리지 않았어요. 조금 더 크게 말해 볼까요?',
      _ when _isPermission(msg) => '마이크 권한이 필요해요. 설정에서 허용해 주세요.',
      'error_network' || 'error_network_timeout' => '음성 인식에 인터넷 연결이 필요해요.',
      _ => '음성 인식 중 문제가 생겼어요. ($msg)',
    };
    _finish(SpeechAttempt.failed(friendly));
  }

  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      _started = true;
      return;
    }
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      // 지금 시도가 듣기를 시작하기 전에 온 '끝남'은 이전 시도의 것이다
      if (!_started) return;
      final attempt = _attempt;
      // 최종 결과 콜백보다 상태 변경이 먼저 올 수 있어 잠깐 기다린다.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (attempt != _attempt) return; // 그사이 새 시도를 시작했다
        _finish(_words.isEmpty ? const SpeechAttempt.failed('잘 들리지 않았어요. 다시 말해 볼까요?') : SpeechAttempt.heard(_words));
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
    // 이전 듣기가 끝나지 않았으면 먼저 끝낸다 (두 번 시작해도 앞 요청이 20초 동안 매달리지 않게)
    _finish(const SpeechAttempt.failed('다시 듣기를 시작했어요.'));
    if (_stt.isListening) await _stt.cancel();
    final attempt = ++_attempt;
    _started = false;
    _words = '';
    final pending = _pending = Completer<SpeechAttempt>();
    try {
      await _stt.listen(
        expected: expected,
        onResult: (words, isFinal) {
          if (attempt != _attempt) return;
          _started = true;
          _words = words;
          onPartial?.call(words);
          if (isFinal) _finish(SpeechAttempt.heard(words));
        },
      );
    } catch (_) {
      _finish(const SpeechAttempt.failed('음성 인식을 시작하지 못했어요. 다시 눌러 주세요.'));
    }
    return pending.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () =>
          _words.isEmpty ? const SpeechAttempt.failed('잘 들리지 않았어요. 다시 말해 볼까요?') : SpeechAttempt.heard(_words),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}

final speechInputProvider = Provider<SpeechInput>((ref) => DeviceSpeechInput());
