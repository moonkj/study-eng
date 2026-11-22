import '../data/models.dart';

/// 화면이 안전하게 그릴 수 있는 팩인지 검사한다. 문제가 없으면 빈 목록.
/// (서버도 검사하지만, 저장된 옛 팩이나 깨진 응답이 앱을 멈추지 않게 한 번 더 확인한다)
List<String> checkPack(DailyPack p) {
  final problems = <String>[];
  if (p.expressions.isEmpty) problems.add('표현이 없어요');
  if (p.words.isEmpty) problems.add('단어가 없어요');
  if (p.sentences.isEmpty) problems.add('따라 말하기 문장이 없어요');
  if (p.quiz.isEmpty) problems.add('퀴즈가 없어요');
  for (final q in p.quiz) {
    if (q.choices.length < 2) problems.add('보기가 부족한 퀴즈: ${q.id}');
    if (q.answerIndex < 0 || q.answerIndex >= q.choices.length) problems.add('정답 위치가 잘못된 퀴즈: ${q.id}');
  }
  for (final e in p.expressions) {
    if (e.examples.isEmpty) problems.add('예문이 없는 표현: ${e.id}');
  }
  final ids = [...p.expressions.map((e) => e.id), ...p.words.map((w) => w.id), ...p.sentences.map((s) => s.id)];
  if (ids.toSet().length != ids.length) problems.add('id 가 겹쳐요');
  return problems;
}
