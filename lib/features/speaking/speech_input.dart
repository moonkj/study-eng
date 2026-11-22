import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 음성 인식 입력. 실제 구현(speech_to_text)은 다음 단계에서 붙인다.
abstract class SpeechInput {
  bool get isDemo;

  /// 사용자가 [target] 문장을 말한 결과(인식된 텍스트)를 돌려준다.
  Future<String> listen(String target);
}

/// 데모용: 짝수 번째 호출에서 한 단어를 살짝 틀린 것으로 돌려준다.
class DemoSpeechInput implements SpeechInput {
  int _calls = 0;

  @override
  bool get isDemo => true;

  @override
  Future<String> listen(String target) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _calls++;
    final words = target.replaceAll(RegExp(r'[,.!?]'), '').split(' ');
    if (_calls.isOdd && words.length > 2) {
      final i = words.length ~/ 2;
      words[i] = _mishear(words[i]);
    }
    return words.join(' ');
  }

  static String _mishear(String w) {
    if (w.contains('tt')) return w.replaceFirst('tt', 'dd');
    if (w.contains('t')) return w.replaceFirst('t', 'd');
    if (w.contains('th')) return w.replaceFirst('th', 's');
    return '${w}s';
  }
}

final speechInputProvider = Provider<SpeechInput>((ref) => DemoSpeechInput());
