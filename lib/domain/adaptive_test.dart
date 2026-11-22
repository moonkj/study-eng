import 'level.dart';

/// 진단 문항 응답 결과. "잘 모르겠어요"는 찍기 방지를 위해 오답처럼 처리한다.
enum Answer { correct, wrong, unsure }

class TestStep {
  const TestStep({required this.step, required this.skill, required this.answer});

  /// 문항 난이도(세부 단계 index, 0~14)
  final int step;
  final Skill skill;
  final Answer answer;

  bool get isCorrect => answer == Answer.correct;
}

/// 적응형 레벨 진단 (계단식).
///
/// - A2.1 난이도에서 시작한다.
/// - 맞히면 난이도를 올리고, 틀리면(또는 모르겠어요) 내린다.
/// - 처음 방향이 바뀌기 전까지는 2칸씩, 그 뒤로는 1칸씩 움직여 빠르게 수렴한다.
/// - 영역 4개를 번갈아 출제해 영역별 레벨도 함께 추정한다.
class AdaptiveTest {
  AdaptiveTest({this.totalItems = 12, this.startStep = 3});

  final int totalItems;
  final int startStep;

  static const skillOrder = [Skill.grammar, Skill.vocabulary, Skill.listening, Skill.speaking];

  final List<TestStep> _history = [];
  int _stride = 2;
  bool? _lastWasCorrect;

  List<TestStep> get history => List.unmodifiable(_history);

  int get answered => _history.length;

  bool get isFinished => _history.length >= totalItems;

  /// 다음 문항의 난이도.
  int get nextStep {
    if (_history.isEmpty) return startStep;
    final last = _history.last;
    final delta = last.isCorrect ? _stride : -_stride;
    return (last.step + delta).clamp(0, Level.stepCount - 1);
  }

  /// 다음 문항의 영역.
  Skill get nextSkill => skillOrder[_history.length % skillOrder.length];

  /// 최근 연속 정답 수 (UI의 "연속 2문제 정답!" 표시용).
  int get correctStreak {
    var n = 0;
    for (final s in _history.reversed) {
      if (!s.isCorrect) break;
      n++;
    }
    return n;
  }

  void record(Answer answer, {int? step, Skill? skill}) {
    if (isFinished) {
      throw StateError('진단이 이미 끝났습니다.');
    }
    final s = TestStep(step: step ?? nextStep, skill: skill ?? nextSkill, answer: answer);
    final correct = s.isCorrect;
    if (_lastWasCorrect != null && _lastWasCorrect != correct) {
      _stride = 1; // 방향이 바뀌면 보폭을 줄인다
    }
    _lastWasCorrect = correct;
    _history.add(s);
  }

  /// 응답 목록으로 실력을 점수화한다.
  /// 맞힌 문항은 그 난이도보다 반 칸 위, 틀린 문항은 한 칸 아래에 실력이 있다고 본다.
  /// (틀린 쪽을 더 크게 반영해야 공통 난이도로 출제된 약한 영역이 드러난다)
  /// 후반 문항(수렴 구간)에 더 큰 가중치를 준다.
  static int estimateScore(List<TestStep> steps) {
    if (steps.isEmpty) return Level.fromStep(3).score;
    var weighted = 0.0;
    var weights = 0.0;
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final w = 1.0 + i; // 뒤쪽 문항일수록 가중치↑
      final ability = s.step + (s.isCorrect ? 0.5 : -1.0);
      weighted += ability * w;
      weights += w;
    }
    final stepEstimate = weighted / weights;
    return ((stepEstimate + 0.5) * Level.pointsPerStep).round();
  }

  /// 영역별 레벨은 문항이 3개 정도뿐이라 따로 추정하면 흔들린다.
  /// 그래서 전체 레벨을 기준으로, 그 영역 문항이 기대와 얼마나 달랐는지만큼 위아래로 보정한다.
  /// - 내 레벨 이상 문항을 맞힘: +1      - 내 레벨보다 쉬운 문항을 맞힘: +0.25
  /// - 내 레벨 이하 문항을 틀림: -1.5    - 내 레벨보다 어려운 문항을 틀림: -0.5
  static int skillScore(int overallScore, List<TestStep> items) {
    if (items.isEmpty) return overallScore;
    final overallStep = overallScore ~/ Level.pointsPerStep;
    var surprise = 0.0;
    for (final s in items) {
      if (s.isCorrect) {
        surprise += s.step >= overallStep ? 1.0 : 0.25;
      } else {
        surprise += s.step <= overallStep ? -1.5 : -0.5;
      }
    }
    return overallScore + (surprise / items.length * Level.pointsPerStep).round();
  }

  LearnerProfile result() {
    final overall = Level(estimateScore(_history));
    return LearnerProfile(
      overall: overall,
      skills: {
        for (final skill in Skill.values)
          skill: Level(skillScore(overall.score, _history.where((s) => s.skill == skill).toList())),
      },
    );
  }
}
