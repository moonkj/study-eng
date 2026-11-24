import '../data/models.dart';
import 'study_log.dart';

/// 처음 며칠은 분량을 줄여 루틴을 끝까지 해 보는 경험을 먼저 준다.
/// 학습 n일차(오늘 이전에 루틴을 끝낸 날 수 + 1)에 따른 최대 분량. 4일차부터는 null (팩 그대로).
({int expressions, int words, int sentences, int quiz})? starterSize(int dayNumber) => switch (dayNumber) {
  <= 1 => (expressions: 2, words: 5, sentences: 5, quiz: 5),
  2 => (expressions: 3, words: 7, sentences: 7, quiz: 7),
  3 => (expressions: 3, words: 8, sentences: 8, quiz: 8),
  _ => null,
};

/// 오늘이 학습 몇 일차인지. 오늘 끝낸 기록은 세지 않아 하루 동안 바뀌지 않는다.
int dayNumberOf(Iterable<String> logKeys, DateTime today) {
  final key = dateKey(today);
  return logKeys.where((k) => k.compareTo(key) < 0).length + 1;
}

/// 받은 팩(서버·기본)을 오늘 보여 줄 팩으로 만든다: 처음 며칠은 분량을 줄이고, 회상형 문제를 붙인다.
/// 같은 입력이면 항상 같은 결과를 낸다 (저장된 진행이 문제 번호로 기록되므로).
DailyPack prepareDailyPack(DailyPack raw, {required int dayNumber}) {
  final trimmed = _trim(raw, starterSize(dayNumber));
  return _withRecall(_withExpressionSentences(trimmed), count: dayNumber <= 1 ? 1 : 2);
}

/// 따라 말하기에 오늘 표현이 쓰인 문장이 없으면 표현마다 첫 예문을 하나씩 붙인다.
/// (표현을 입으로 익혀야 실제로 쓸 수 있다. 서버 팩이 이미 표현 문장을 넣었으면 그대로 둔다)
DailyPack _withExpressionSentences(DailyPack p) {
  final ids = {for (final s in p.sentences) s.id};
  final extra = <Sentence>[
    for (final e in p.expressions)
      if (e.examples.isNotEmpty &&
          !p.sentences.any((s) => s.en.toLowerCase().contains(e.highlight.toLowerCase())) &&
          !ids.contains('x-${e.id}'))
        Sentence(id: 'x-${e.id}', en: e.examples.first.en, ko: e.examples.first.ko, focus: e.highlight),
  ];
  if (extra.isEmpty) return p;
  return _copy(p, sentences: [...p.sentences, ...extra]);
}

DailyPack _trim(DailyPack p, ({int expressions, int words, int sentences, int quiz})? size) {
  if (size == null) return p;
  final expressions = p.expressions.take(size.expressions).toList();
  final words = p.words.take(size.words).toList();
  final dropped = {
    for (final e in p.expressions.skip(size.expressions)) e.id,
    for (final w in p.words.skip(size.words)) w.id,
  };
  final kept = {for (final w in words) w.word.toLowerCase()};
  // 남긴 단어를 쓰는 문장을 먼저, 모자라면 나머지 문장으로 채운다 (원래 순서 유지)
  final focused = p.sentences.where((s) => kept.contains(s.focus.toLowerCase())).take(size.sentences).toSet();
  final rest = p.sentences.where((s) => !focused.contains(s)).take(size.sentences - focused.length).toSet();
  final sentences = p.sentences.where((s) => focused.contains(s) || rest.contains(s)).toList();
  // 빠진 표현·단어를 묻는 새 문제는 뺀다 (복습 문제는 예전에 배운 것이라 남긴다)
  final allowed = p.quiz.where((q) => q.isReview || q.itemId == null || !dropped.contains(q.itemId)).toList();
  // 남긴 표현마다 그 표현을 묻는 문제를 하나씩 먼저 고르고, 나머지는 원래 순서대로 채운다
  final picked = <QuizItem>{
    for (final e in expressions) ?allowed.where((q) => q.itemId == e.id).firstOrNull,
  }.take(size.quiz).toSet();
  for (final q in allowed) {
    if (picked.length >= size.quiz) break;
    picked.add(q);
  }
  final quiz = allowed.where(picked.contains).toList();
  return _copy(p, expressions: expressions, words: words, sentences: sentences, quiz: quiz);
}

/// 오늘 단어 중 [count]개를 '첫 글자 단서 보고 쓰기' 문제로 만들어 퀴즈 끝에 붙인다.
/// 고르는 문제로 이미 묻지 않은 단어를 먼저 쓰고, 예문에 단어가 그대로 들어 있어야 만든다.
DailyPack _withRecall(DailyPack p, {required int count}) {
  final asked = {for (final q in p.quiz) ?q.itemId};
  final candidates = [...p.words.where((w) => !asked.contains(w.id)), ...p.words.where((w) => asked.contains(w.id))];
  final ids = {for (final q in p.quiz) q.id};
  final recall = <QuizItem>[];
  for (final w in candidates) {
    if (recall.length >= count) break;
    final item = recallItemFor(w);
    if (item == null || ids.contains(item.id)) continue;
    recall.add(item);
  }
  if (recall.isEmpty) return p;
  return _copy(p, quiz: [...p.quiz, ...recall]);
}

/// 단어 예문에서 단어를 첫 글자만 남기고 가린 회상형 문제. 예문에 단어가 그대로 없으면 null.
QuizItem? recallItemFor(Word w) {
  final en = w.example.en;
  final m = RegExp('\\b${RegExp.escape(w.word)}\\b', caseSensitive: false).firstMatch(en);
  if (m == null) return null;
  final answer = m.group(0)!;
  final clue = '${en.substring(0, m.start)}${blankFor(answer)}${en.substring(m.end)}';
  return QuizItem(
    id: 'r-${w.id}',
    itemId: w.id,
    prompt: w.example.ko,
    choices: [answer],
    answerIndex: 0,
    clue: clue,
    accept: [if (answer.toLowerCase() != w.word.toLowerCase()) w.word],
    explanation: '${w.word} ${w.ipa} — ${w.meaning}',
  );
}

/// "actually" → "a_______", "on time" → "o_ t___" (단어마다 첫 글자만 보인다)
String blankFor(String answer) =>
    answer.split(' ').map((part) => part.isEmpty ? part : part[0] + '_' * (part.length - 1)).join(' ');

/// 입력한 답이 회상형 문제의 정답인지 (대소문자·앞뒤 공백·문장부호·곧은/굽은 따옴표 차이는 무시)
bool isRecallCorrect(QuizItem q, String typed) {
  final t = normalizeAnswer(typed);
  if (t.isEmpty) return false;
  return [...q.choices.take(1), ...q.accept].any((a) => normalizeAnswer(a) == t);
}

String normalizeAnswer(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[‘’`´]'), "'")
    .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

DailyPack _copy(
  DailyPack p, {
  List<Expression>? expressions,
  List<Word>? words,
  List<Sentence>? sentences,
  List<QuizItem>? quiz,
}) => DailyPack(
  date: p.date,
  topic: p.topic,
  contentStep: p.contentStep,
  fromClaude: p.fromClaude,
  expressions: expressions ?? p.expressions,
  words: words ?? p.words,
  sentences: sentences ?? p.sentences,
  quiz: quiz ?? p.quiz,
  dialogue: p.dialogue,
);
