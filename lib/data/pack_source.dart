import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../domain/level.dart';
import '../domain/srs.dart';
import '../domain/study_log.dart';
import 'models.dart';

/// 지금까지 배운 표현·단어 (복습 문제를 만들고 중복을 피하는 데 쓴다)
class LearnedItem {
  const LearnedItem({
    required this.id,
    required this.kind,
    required this.text,
    required this.meaning,
    required this.firstSeen,
  });

  final String id;

  /// 'expression' | 'word'
  final String kind;
  final String text;
  final String meaning;

  /// 처음 배운 날 (yyyy-MM-dd)
  final String firstSeen;

  Map<String, Object?> toJson() => {'kind': kind, 'text': text, 'meaning': meaning, 'firstSeen': firstSeen};

  factory LearnedItem.fromJson(String id, Map<String, Object?> j) => LearnedItem(
    id: id,
    kind: j['kind'] as String,
    text: j['text'] as String,
    meaning: j['meaning'] as String,
    firstSeen: j['firstSeen'] as String,
  );
}

/// 오늘 팩의 표현·단어를 배운 항목으로 등록한다 (이미 있으면 처음 배운 날을 유지).
Map<String, LearnedItem> registerLearned(Map<String, LearnedItem> learned, DailyPack pack) {
  final day = dateKey(pack.date);
  return {
    ...learned,
    for (final e in pack.expressions)
      if (!learned.containsKey(e.id))
        e.id: LearnedItem(id: e.id, kind: 'expression', text: e.pattern, meaning: e.meaning, firstSeen: day),
    for (final w in pack.words)
      if (!learned.containsKey(w.id))
        w.id: LearnedItem(id: w.id, kind: 'word', text: w.word, meaning: w.meaning, firstSeen: day),
  };
}

/// "어제 배운 단어", "5일 전에 배운 표현"
String reviewLabelFor(LearnedItem item, DateTime today) {
  final days = dateOnly(today).difference(parseDateKey(item.firstSeen)).inDays;
  final what = item.kind == 'word' ? '단어' : '표현';
  if (days <= 1) return '어제 배운 $what';
  if (days >= 7 && days % 7 == 0) return '${days ~/ 7}주 전에 배운 $what';
  return '$days일 전에 배운 $what';
}

/// 서버에 보낼 요청 본문
Map<String, Object?> buildPackRequest({
  required DateTime date,
  required LearnerProfile profile,
  required int contentStep,
  required Map<String, LearnedItem> learned,
  required Map<String, ReviewCard> cards,
}) {
  final today = dateOnly(date);
  bool recent(LearnedItem i, int days) => today.difference(parseDateKey(i.firstSeen)).inDays <= days;
  final due = Srs.dueToday(cards.values.where((c) => learned.containsKey(c.itemId)), today, limit: 4);
  final focus = profile.weakestSkill;
  return {
    'date': dateKey(today),
    'level': profile.overall.label,
    'contentLevel': Level.fromStep(contentStep).label,
    'skills': {for (final e in profile.skills.entries) e.key.name: e.value.label},
    'focusSkill': focus.name,
    'speakingSentences': focus == Skill.speaking ? 12 : 10,
    'avoid': {
      'expressions': [
        for (final i in learned.values)
          if (i.kind == 'expression' && recent(i, 60)) i.text,
      ].take(200).toList(),
      'words': [
        for (final i in learned.values)
          if (i.kind == 'word' && recent(i, 90)) i.text,
      ].take(400).toList(),
    },
    'review': [
      for (final c in due)
        {
          'id': c.itemId,
          'kind': learned[c.itemId]!.kind,
          'text': learned[c.itemId]!.text,
          'meaning': learned[c.itemId]!.meaning,
        },
    ],
  };
}

/// 서버 응답(JSON) → DailyPack
DailyPack packFromJson(Map<String, Object?> j, {required Map<String, LearnedItem> learned, required DateTime today}) {
  Example ex(Object? o) {
    final m = (o as Map).cast<String, Object?>();
    return Example(m['en'] as String, m['ko'] as String);
  }

  List<Map<String, Object?>> list(String key) => [for (final e in j[key] as List) (e as Map).cast<String, Object?>()];

  return DailyPack(
    date: parseDateKey(j['date'] as String),
    topic: j['topic'] as String,
    contentStep: Level.parse(j['contentLevel'] as String? ?? '')?.step ?? 6,
    fromClaude: true,
    expressions: [
      for (final e in list('expressions'))
        Expression(
          id: e['id'] as String,
          pattern: e['pattern'] as String,
          highlight: e['highlight'] as String,
          meaning: e['meaning'] as String,
          usage: e['usage'] as String,
          examples: [for (final x in e['examples'] as List) ex(x)],
          compare: e['compare'] == null
              ? null
              : ((e['compare'] as Map)['en'] as String, (e['compare'] as Map)['ko'] as String),
          levelLabel: e['level'] as String? ?? '',
          topic: e['topic'] as String? ?? j['topic'] as String,
        ),
    ],
    words: [
      for (final w in list('words'))
        Word(
          id: w['id'] as String,
          word: w['word'] as String,
          posEn: w['posEn'] as String,
          posKo: w['posKo'] as String,
          meaning: w['meaning'] as String,
          ipa: w['ipa'] as String,
          pronKo: w['pronKo'] as String,
          example: ex(w['example']),
          levelLabel: w['level'] as String? ?? '',
        ),
    ],
    sentences: [
      for (final s in list('sentences'))
        Sentence(id: s['id'] as String, en: s['en'] as String, ko: s['ko'] as String, focus: s['focus'] as String),
    ],
    quiz: [
      for (final q in list('quiz'))
        QuizItem(
          id: q['id'] as String,
          prompt: q['prompt'] as String,
          choices: (q['choices'] as List).cast<String>(),
          answerIndex: (q['answerIndex'] as num).toInt(),
          explanation: q['explanation'] as String,
          itemId: q['itemId'] as String?,
          reviewLabel: q['reviewOf'] == null || learned[q['reviewOf']] == null
              ? null
              : reviewLabelFor(learned[q['reviewOf']]!, today),
        ),
    ],
  );
}

class PackFetchException implements Exception {
  const PackFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 학습 팩을 받아오는 곳
abstract class PackSource {
  Future<Map<String, Object?>> fetch(Map<String, Object?> request);
}

/// 내 Cloud Functions(또는 로컬 개발 서버)에서 받아온다.
class RemotePackSource implements PackSource {
  RemotePackSource({required this.url, required this.token, http.Client? client}) : _client = client ?? http.Client();

  final String url;
  final String token;
  final http.Client _client;

  @override
  Future<Map<String, Object?>> fetch(Map<String, Object?> request) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(url),
            headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
            body: jsonEncode(request),
          )
          // 서버 함수 제한 시간(180초)보다 길게: 앱이 먼저 포기해 서버 비용만 나가는 일이 없게
          .timeout(const Duration(seconds: 190));
    } on TimeoutException {
      throw const PackFetchException('학습 팩을 만드는 데 시간이 너무 오래 걸려요.');
    } catch (_) {
      throw const PackFetchException('서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.');
    }
    if (res.statusCode != 200) {
      throw PackFetchException(switch (res.statusCode) {
        401 => '서버 토큰이 맞지 않아요. 앱 설정을 확인해 주세요.',
        503 => '요청이 많아요. 잠시 뒤에 다시 시도해 주세요.',
        _ => '학습 팩을 만들지 못했어요. (${res.statusCode})',
      });
    }
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, Object?>();
  }
}

/// 빌드할 때 --dart-define 으로 서버 주소와 토큰을 넣는다. 없으면 샘플 팩으로 동작한다.
const contentApiUrl = String.fromEnvironment('CONTENT_API_URL');
const contentApiToken = String.fromEnvironment('CONTENT_API_TOKEN');

final packSourceProvider = Provider<PackSource?>((ref) {
  if (contentApiUrl.isEmpty || contentApiToken.isEmpty) return null;
  return RemotePackSource(url: contentApiUrl, token: contentApiToken);
});
