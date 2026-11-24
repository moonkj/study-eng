import 'dart:async';

import '../speaking/speech_input.dart';

/// 정해진 시간 동안 계속 듣는다.
/// 기기 음성 인식은 잠깐 멈추면 끝나 버리므로, 시간이 남아 있으면 이어서 다시 듣고 들린 말을 이어 붙인다.
/// 끝내는 것은 [stop] (화면의 시간이 다 됐을 때).
class TimedListen {
  TimedListen(this.input, {required this.expected, required this.onText, this.onError});

  final SpeechInput input;

  /// 인식 힌트로 쓰지는 않는다 (문장 읽기 원문 등, 기록용)
  final String expected;

  /// 지금까지 들린 전체 말 (중간 결과 포함)
  final void Function(String text) onText;

  /// 계속할 수 없는 오류 (마이크 권한 등)
  final void Function(String message)? onError;

  final _done = Completer<String>();
  bool _stopped = false;
  String _committed = '';

  String get text => _committed;
  bool get stopped => _stopped;

  static bool _fatal(String? error) =>
      error != null && (error.contains('권한') || error.contains('쓸 수 없어요') || error.contains('시작하지 못했어요'));

  String _join(String a, String b) => a.isEmpty ? b.trim() : (b.trim().isEmpty ? a : '$a ${b.trim()}');

  Future<void> start() async {
    var fails = 0;
    while (!_stopped) {
      final attempt = await input.listen(expected: expected, onPartial: (p) => onText(_join(_committed, p)));
      if (attempt.ok) {
        _committed = _join(_committed, attempt.text!);
        onText(_committed);
        fails = 0;
      } else if (!_stopped && _fatal(attempt.error)) {
        onError?.call(attempt.error!);
        break;
      } else {
        fails++;
      }
      if (_stopped) break;
      // 바로 다시 시작하면 같은 오류가 빠르게 반복되므로 잠깐 쉰다
      await Future<void>.delayed(Duration(milliseconds: fails > 0 ? 500 : 250));
    }
    if (!_done.isCompleted) _done.complete(_committed);
  }

  /// 듣기를 끝내고, 마지막으로 들린 말까지 붙인 결과를 돌려준다.
  Future<String> stop() async {
    if (!_stopped) {
      _stopped = true;
      await input.stop();
    }
    return _done.future.timeout(const Duration(seconds: 2), onTimeout: () => _committed);
  }
}
