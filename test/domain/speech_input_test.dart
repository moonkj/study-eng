import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/features/speaking/speech_input.dart';

/// 실제 기기처럼 상태·결과 알림을 늦게 보내는 가짜 엔진
class FakeEngine implements SttEngine {
  late void Function(String) onStatus;
  late void Function(String) onError;
  void Function(String, bool)? onResult;
  bool listening = false;
  int listens = 0;

  @override
  Future<bool> initialize({required void Function(String) onError, required void Function(String) onStatus}) async {
    this.onError = onError;
    this.onStatus = onStatus;
    return true;
  }

  @override
  Future<void> listen({required String expected, required void Function(String, bool) onResult}) async {
    this.onResult = onResult;
    listening = true;
    listens++;
  }

  @override
  Future<void> stop() async => listening = false;

  @override
  Future<void> cancel() async => listening = false;

  @override
  bool get isListening => listening;
}

void main() {
  test('같은 문장을 다시 말하면, 첫 시도의 늦은 끝남 알림이 두 번째 시도를 끝내지 않는다', () async {
    final engine = FakeEngine();
    final input = DeviceSpeechInput(engine: engine);

    final first = input.listen(expected: 'I usually take the bus.');
    await Future<void>.delayed(Duration.zero);
    engine.onStatus('listening');
    engine.onResult!('I usually take the bus', false);
    engine.onStatus('done'); // 결과보다 끝남이 먼저 → 400ms 뒤 마무리 예약
    expect((await first).text, 'I usually take the bus');

    // 두 번째 시도: 시작 직후 첫 시도의 notListening/done 이 늦게 도착
    final second = input.listen(expected: 'I usually take the bus.');
    await Future<void>.delayed(Duration.zero);
    engine.onStatus('notListening');
    engine.onError('error_no_match');
    var finished = false;
    second.then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(finished, isFalse); // 아직 듣는 중

    engine.onStatus('listening');
    engine.onResult!('I usually take the bus to work', true);
    expect((await second).text, 'I usually take the bus to work');
    expect(engine.listens, 2);
  });

  test('듣기 중 실제 오류는 그 시도의 실패로 알린다', () async {
    final engine = FakeEngine();
    final input = DeviceSpeechInput(engine: engine);
    final a = input.listen(expected: 'Hi.');
    await Future<void>.delayed(Duration.zero);
    engine.onStatus('listening');
    engine.onError('error_no_match');
    expect((await a).error, contains('잘 들리지 않았어요'));
  });
}
