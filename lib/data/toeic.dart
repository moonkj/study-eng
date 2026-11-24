import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/study_log.dart';

/// 문항 난이도 단계 (모범 답안·핵심 표현도 이 단계별로 있다)
enum ToeicTier { basic, ih, al }

ToeicTier _tierOf(Object? raw) => switch ('$raw'.toUpperCase()) {
  'IH' => ToeicTier.ih,
  'AL' => ToeicTier.al,
  _ => ToeicTier.basic,
};

/// 목표 등급 (토익스피킹 공식 점수 구간)
enum ToeicTarget {
  im1(110, 'IM1', '110-120', ToeicTier.basic, 5),
  im2(130, 'IM2', '130', ToeicTier.basic, 6),
  im3(140, 'IM3', '140-150', ToeicTier.basic, 7),
  ih(160, 'IH', '160-170', ToeicTier.ih, 9),
  al(180, 'AL', '180-200', ToeicTier.al, 11);

  const ToeicTarget(this.score, this.label, this.range, this.tier, this.contentStep);

  /// 목표 점수 (설정에 저장하는 값)
  final int score;
  final String label;

  /// 공식 점수 구간
  final String range;
  final ToeicTier tier;

  /// 표현·단어 난이도 단계 (Level step 0~14)
  final int contentStep;

  static const fallback = ToeicTarget.im3;

  static ToeicTarget fromScore(int? score) =>
      ToeicTarget.values.firstWhere((t) => t.score == score, orElse: () => fallback);

  /// 한 단계 위 목표 (이미 최고면 null)
  ToeicTarget? get next => index + 1 < ToeicTarget.values.length ? ToeicTarget.values[index + 1] : null;
}

/// 토익스피킹 등급 (낮은 것부터)
const toeicLevels = ['NL', 'NM', 'NH', 'IL', 'IM1', 'IM2', 'IM3', 'IH', 'AL'];

int toeicLevelIndex(String level) => toeicLevels.indexOf(level.toUpperCase());

/// [level] 이 [target] 이상인지
bool meetsTarget(String level, ToeicTarget target) {
  final i = toeicLevelIndex(level);
  return i >= 0 && i >= toeicLevelIndex(target.label);
}

/// 단계별 값: 없는 단계는 바로 아래 단계 값을 쓴다
class Tiered<T> {
  const Tiered(this.basic, [this.ih, this.al]);
  final T basic;
  final T? ih;
  final T? al;

  T at(ToeicTier tier) => switch (tier) {
    ToeicTier.basic => basic,
    ToeicTier.ih => ih ?? basic,
    ToeicTier.al => al ?? ih ?? basic,
  };
}

List<String> _strings(Object? raw) => [
  for (final v in (raw is List ? raw : const [])) ?(v is String && v.trim().isNotEmpty ? v : null),
];

String _str(Map j, String key) {
  final v = j[key];
  if (v is! String || v.trim().isEmpty) throw FormatException('$key 없음');
  return v;
}

Tiered<List<String>> _phrases(Map j) {
  final ih = _strings(j['keyPhrasesIH']);
  final al = _strings(j['keyPhrasesAL']);
  return Tiered(_strings(j['keyPhrases']), ih.isEmpty ? null : ih, al.isEmpty ? null : al);
}

Tiered<String> _model(Map j) {
  String? opt(String k) => j[k] is String && (j[k] as String).trim().isNotEmpty ? j[k] as String : null;
  return Tiered(_str(j, 'model'), opt('modelIH'), opt('modelAL'));
}

Tiered<List<String>> _models(Map j) {
  List<String>? opt(String k) {
    final l = _strings(j[k]);
    return l.length == 3 ? l : null;
  }

  final basic = _strings(j['models']);
  if (basic.length != 3) throw const FormatException('models 3개 필요');
  return Tiered(basic, opt('modelsIH'), opt('modelsAL'));
}

class ReadAloudItem {
  const ReadAloudItem({required this.id, required this.text, this.tips = const [], this.level = ToeicTier.basic});
  final String id;
  final String text;
  final List<String> tips;
  final ToeicTier level;

  factory ReadAloudItem.fromJson(Map j) =>
      ReadAloudItem(id: _str(j, 'id'), text: _str(j, 'text'), tips: _strings(j['tips']), level: _tierOf(j['level']));
}

class PictureItem {
  const PictureItem({
    required this.id,
    required this.file,
    this.credit = '',
    this.place = '',
    required this.model,
    this.keyPhrases = const Tiered([]),
    this.vocab = const [],
    this.level = ToeicTier.basic,
  });
  final String id;
  final String file;
  final String credit;
  final String place;
  final Tiered<String> model;
  final Tiered<List<String>> keyPhrases;
  final List<({String en, String ko})> vocab;
  final ToeicTier level;

  factory PictureItem.fromJson(Map j) => PictureItem(
    id: _str(j, 'id'),
    file: _str(j, 'file'),
    credit: j['credit'] as String? ?? '',
    place: j['place'] as String? ?? '',
    model: _model(j),
    keyPhrases: _phrases(j),
    vocab: [
      for (final v in (j['vocab'] is List ? j['vocab'] as List : const []))
        if (v is Map && v['en'] is String && v['ko'] is String) (en: v['en'] as String, ko: v['ko'] as String),
    ],
    level: _tierOf(j['level']),
  );
}

class QuestionSet {
  const QuestionSet({
    required this.id,
    required this.setting,
    required this.questions,
    required this.models,
    this.keyPhrases = const Tiered([]),
    this.level = ToeicTier.basic,
  });
  final String id;
  final String setting;
  final List<String> questions;
  final Tiered<List<String>> models;
  final Tiered<List<String>> keyPhrases;
  final ToeicTier level;

  factory QuestionSet.fromJson(Map j) {
    final q = _strings(j['questions']);
    if (q.length != 3) throw const FormatException('questions 3개 필요');
    return QuestionSet(
      id: _str(j, 'id'),
      setting: _str(j, 'setting'),
      questions: q,
      models: _models(j),
      keyPhrases: _phrases(j),
      level: _tierOf(j['level']),
    );
  }
}

class InfoTable {
  const InfoTable({
    required this.title,
    this.subtitle,
    required this.columns,
    required this.rows,
    this.notes = const [],
  });
  final String title;
  final String? subtitle;
  final List<String> columns;
  final List<List<String>> rows;
  final List<String> notes;

  factory InfoTable.fromJson(Map j) => InfoTable(
    title: _str(j, 'title'),
    subtitle: j['subtitle'] as String?,
    columns: _strings(j['columns']),
    rows: [
      for (final r in (j['rows'] is List ? j['rows'] as List : const []))
        if (r is List) [for (final c in r) '${c ?? ''}'],
    ],
    notes: _strings(j['notes']),
  );
}

class InfoSet {
  const InfoSet({
    required this.id,
    required this.table,
    required this.intro,
    required this.questions,
    required this.models,
    this.keyPhrases = const Tiered([]),
    this.level = ToeicTier.basic,
  });
  final String id;
  final InfoTable table;
  final String intro;
  final List<String> questions;
  final Tiered<List<String>> models;
  final Tiered<List<String>> keyPhrases;
  final ToeicTier level;

  factory InfoSet.fromJson(Map j) {
    final q = _strings(j['questions']);
    if (q.length != 3) throw const FormatException('questions 3개 필요');
    return InfoSet(
      id: _str(j, 'id'),
      table: InfoTable.fromJson(j['table'] as Map),
      intro: _str(j, 'intro'),
      questions: q,
      models: _models(j),
      keyPhrases: _phrases(j),
      level: _tierOf(j['level']),
    );
  }
}

class OpinionItem {
  const OpinionItem({
    required this.id,
    required this.question,
    required this.model,
    this.keyPhrases = const Tiered([]),
    this.level = ToeicTier.basic,
  });
  final String id;
  final String question;
  final Tiered<String> model;
  final Tiered<List<String>> keyPhrases;
  final ToeicTier level;

  factory OpinionItem.fromJson(Map j) => OpinionItem(
    id: _str(j, 'id'),
    question: _str(j, 'question'),
    model: _model(j),
    keyPhrases: _phrases(j),
    level: _tierOf(j['level']),
  );
}

/// 토익스피킹 문항 모음 (assets/toeic/content.json)
class ToeicBank {
  const ToeicBank({
    this.readAloud = const [],
    this.pictures = const [],
    this.questions = const [],
    this.infoTables = const [],
    this.opinions = const [],
  });
  final List<ReadAloudItem> readAloud;
  final List<PictureItem> pictures;
  final List<QuestionSet> questions;
  final List<InfoSet> infoTables;
  final List<OpinionItem> opinions;

  /// 하루 세트·모의고사를 만들 수 있는지 (유형마다 최소 1개)
  bool get usable =>
      readAloud.isNotEmpty &&
      pictures.isNotEmpty &&
      questions.isNotEmpty &&
      infoTables.isNotEmpty &&
      opinions.isNotEmpty;

  /// 문항 하나가 깨져도 나머지는 쓴다
  static List<T> _list<T>(Object? raw, T Function(Map) read) {
    final out = <T>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(read(e));
      } catch (_) {}
    }
    return out;
  }

  factory ToeicBank.fromJson(Map j) => ToeicBank(
    readAloud: _list(j['readAloud'], ReadAloudItem.fromJson),
    pictures: _list(j['pictures'], PictureItem.fromJson),
    questions: _list(j['questions'], QuestionSet.fromJson),
    infoTables: _list(j['infoTables'], InfoSet.fromJson),
    opinions: _list(j['opinions'], OpinionItem.fromJson),
  );

  static ToeicBank parse(String raw) => ToeicBank.fromJson(jsonDecode(raw) as Map);
}

const toeicAssetPath = 'assets/toeic/content.json';

/// 앱 안의 문항 모음을 읽는다. 파일이 없거나 깨졌으면 null (말하기 단계는 예전 따라 말하기로 대신한다).
Future<ToeicBank?> loadToeicBank() async {
  try {
    final bank = ToeicBank.parse(await rootBundle.loadString(toeicAssetPath));
    return bank.usable ? bank : null;
  } catch (_) {
    return null;
  }
}

/// 문항 모음. main() 에서 미리 읽어 넣는다 (화면이 열린 뒤 내용이 바뀌지 않게). 테스트는 작은 모음으로 덮어쓴다.
final toeicBankProvider = Provider<ToeicBank?>((ref) => null);

// ───────────────────────── 세트 고르기 ─────────────────────────

/// 목표 단계 문항부터, 없으면 가까운 단계 순서로
List<ToeicTier> tierOrder(ToeicTier t) => switch (t) {
  ToeicTier.basic => const [ToeicTier.basic, ToeicTier.ih, ToeicTier.al],
  ToeicTier.ih => const [ToeicTier.ih, ToeicTier.basic, ToeicTier.al],
  ToeicTier.al => const [ToeicTier.al, ToeicTier.ih, ToeicTier.basic],
};

/// [items] 중 [tier] 에 맞는 것 (없으면 가까운 단계)
List<T> poolFor<T>(List<T> items, ToeicTier Function(T) levelOf, ToeicTier tier) {
  for (final t in tierOrder(tier)) {
    final pool = items.where((e) => levelOf(e) == t).toList();
    if (pool.isNotEmpty) return pool;
  }
  return items;
}

T pickFor<T>(List<T> items, ToeicTier Function(T) levelOf, ToeicTier tier, int n) {
  final pool = poolFor(items, levelOf, tier);
  return pool[n % pool.length];
}

/// 날짜를 일 수로 (세트를 날짜마다 정해진 대로 고르기 위해)
int dayIndexOf(DateTime d) => daysBetween(DateTime(2024, 1, 1), DateTime(d.year, d.month, d.day));

/// 매일 돌아가며 하나씩 나오는 묶음
enum ToeicBlock { respond, info, opinion }

/// 오늘의 토스 세트: 문장 읽기 1 + 사진 묘사 1 + 돌아가는 묶음 1
class ToeicDailySet {
  const ToeicDailySet({
    required this.readAloud,
    required this.picture,
    required this.block,
    this.respond,
    this.info,
    this.opinion,
  });
  final ReadAloudItem readAloud;
  final PictureItem picture;
  final ToeicBlock block;
  final QuestionSet? respond;
  final InfoSet? info;
  final OpinionItem? opinion;
}

ToeicDailySet dailySetFor(ToeicBank bank, DateTime date, ToeicTarget target) {
  final d = dayIndexOf(date);
  final tier = target.tier;
  final block = ToeicBlock.values[d % 3];
  final n = d ~/ 3;
  return ToeicDailySet(
    readAloud: pickFor(bank.readAloud, (e) => e.level, tier, d),
    picture: pickFor(bank.pictures, (e) => e.level, tier, d),
    block: block,
    respond: block == ToeicBlock.respond ? pickFor<QuestionSet>(bank.questions, (e) => e.level, tier, n) : null,
    info: block == ToeicBlock.info ? pickFor<InfoSet>(bank.infoTables, (e) => e.level, tier, n) : null,
    opinion: block == ToeicBlock.opinion ? pickFor<OpinionItem>(bank.opinions, (e) => e.level, tier, n) : null,
  );
}

/// 모의고사 11문항 세트
class ToeicMockSet {
  const ToeicMockSet({
    required this.readAloud,
    required this.pictures,
    required this.respond,
    required this.info,
    required this.opinion,
  });
  final List<ReadAloudItem> readAloud;
  final List<PictureItem> pictures;
  final QuestionSet respond;
  final InfoSet info;
  final OpinionItem opinion;
}

ToeicMockSet mockSetFor(ToeicBank bank, DateTime date, ToeicTarget target) {
  // 오늘의 세트와 겹치지 않게 다른 순번으로 고른다
  final d = dayIndexOf(date) * 7 + 3;
  final tier = target.tier;
  List<T> two<T>(List<T> items, ToeicTier Function(T) levelOf) {
    final pool = poolFor(items, levelOf, tier);
    if (pool.length == 1) return [pool[0], pool[0]];
    return [pool[d % pool.length], pool[(d + 1) % pool.length]];
  }

  return ToeicMockSet(
    readAloud: two(bank.readAloud, (e) => e.level),
    pictures: two(bank.pictures, (e) => e.level),
    respond: pickFor(bank.questions, (e) => e.level, tier, d),
    info: pickFor(bank.infoTables, (e) => e.level, tier, d),
    opinion: pickFor(bank.opinions, (e) => e.level, tier, d),
  );
}
