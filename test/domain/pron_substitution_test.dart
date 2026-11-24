import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/domain/pron_substitution.dart';

void main() {
  test('think → sink 처럼 바꿔 들린 단어와 소리 쌍 요령을 찾는다', () {
    final subs = findSubstitutions('I think so.', 'I sink so');
    expect(subs.single.said, 'think');
    expect(subs.single.heard, 'sink');
    expect(subs.single.tip, contains('th'));
  });

  test('r/l · v/b · 끝소리 빠뜨림', () {
    expect(pairTip('right', 'light'), contains("'r'"));
    expect(pairTip('vest', 'best'), contains("'v'"));
    expect(pairTip('works', 'work'), contains('끝'));
    expect(pairTip('coffee', 'table'), isNull);
  });

  test('엉뚱한 단어나 개수가 맞지 않는 구간은 짝짓지 않는다', () {
    expect(findSubstitutions('I usually take the bus.', 'I usually take the bus'), isEmpty);
    expect(findSubstitutions('Could you help me?', 'Could you elephant giraffe me'), isEmpty);
  });
}
