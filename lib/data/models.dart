import '../domain/level.dart';

class Example {
  const Example(this.en, this.ko);
  final String en;
  final String ko;
}

class Expression {
  const Expression({
    required this.id,
    required this.pattern,
    required this.highlight,
    required this.meaning,
    required this.usage,
    required this.examples,
    this.compare,
    required this.levelLabel,
    required this.topic,
  });

  final String id;

  /// "I've been meaning to ~"
  final String pattern;

  /// 형광펜 칠할 부분 "been meaning to"
  final String highlight;
  final String meaning;
  final String usage;
  final List<Example> examples;

  /// 헷갈리기 쉬운 표현 (영어, 설명)
  final (String, String)? compare;
  final String levelLabel;
  final String topic;
}

class Word {
  const Word({
    required this.id,
    required this.word,
    required this.posEn,
    required this.posKo,
    required this.meaning,
    required this.ipa,
    required this.pronKo,
    required this.example,
    required this.levelLabel,
  });

  final String id;
  final String word;
  final String posEn;
  final String posKo;
  final String meaning;
  final String ipa;
  final String pronKo;
  final Example example;
  final String levelLabel;
}

class Sentence {
  const Sentence({required this.id, required this.en, required this.ko, required this.focus});
  final String id;
  final String en;
  final String ko;

  /// 오늘 단어 중 이 문장에 쓰인 단어
  final String focus;
}

class QuizItem {
  const QuizItem({
    required this.id,
    required this.prompt,
    required this.choices,
    required this.answerIndex,
    required this.explanation,
    this.reviewLabel,
  });

  final String id;

  /// 한국어 문장
  final String prompt;
  final List<String> choices;
  final int answerIndex;
  final String explanation;

  /// 복습 문제면 "3일 전에 배운 표현" 같은 라벨
  final String? reviewLabel;

  bool get isReview => reviewLabel != null;
}

class DailyPack {
  const DailyPack({
    required this.date,
    required this.topic,
    required this.contentStep,
    required this.expressions,
    required this.words,
    required this.sentences,
    required this.quiz,
  });

  final DateTime date;
  final String topic;
  final int contentStep;
  final List<Expression> expressions;
  final List<Word> words;
  final List<Sentence> sentences;
  final List<QuizItem> quiz;

  int get reviewCount => quiz.where((q) => q.isReview).length;
}

/// 레벨 진단 문항
class LevelTestItem {
  const LevelTestItem({
    required this.step,
    required this.skill,
    required this.instruction,
    required this.sentence,
    required this.translation,
    required this.choices,
    required this.answerIndex,
  });

  final int step;
  final Skill skill;
  final String instruction;

  /// 빈칸은 "___"
  final String sentence;
  final String translation;
  final List<String> choices;
  final int answerIndex;
}
