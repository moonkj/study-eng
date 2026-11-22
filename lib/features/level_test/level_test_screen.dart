import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/sample_content.dart';
import '../../domain/adaptive_test.dart';
import '../../domain/level.dart';

class LevelTestScreen extends ConsumerStatefulWidget {
  const LevelTestScreen({super.key});

  @override
  ConsumerState<LevelTestScreen> createState() => _LevelTestScreenState();
}

class _LevelTestScreenState extends ConsumerState<LevelTestScreen> {
  final _test = AdaptiveTest();
  final _used = <LevelTestItem>{};
  late LevelTestItem _item = _pick();
  int? _selected;

  LevelTestItem _pick() {
    final item = pickTestItem(_test.nextStep, _test.nextSkill, _used);
    _used.add(item);
    return item;
  }

  void _submit(Answer answer) {
    _test.record(answer, step: _item.step, skill: _item.skill);
    if (_test.isFinished) {
      ref.read(studyProvider.notifier).applyLevelTest(_test.result());
      context.pushReplacement('/level-result');
      return;
    }
    setState(() {
      _item = _pick();
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final current = Level.fromStep(item.step);
    final hasBlank = item.sentence.contains('___');

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(tooltip: '진단 닫기', onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _test.totalItems; i++)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(right: i == _test.totalItems - 1 ? 0 : 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: i < _test.answered
                                    ? AppColors.ink
                                    : i == _test.answered
                                    ? AppColors.penBlue
                                    : AppColors.track,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_test.answered + 1}/${_test.totalItems}',
                    style: sans(13, weight: FontWeight.w600, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                children: [
                  _DifficultyCard(test: _test, current: current),
                  const SizedBox(height: 32),
                  Text(
                    item.skill.ko,
                    style: sans(13, weight: FontWeight.w600, color: AppColors.penBlue, letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(item.instruction, style: sans(19, weight: FontWeight.w600, height: 1.45)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasBlank)
                          _BlankSentence(item.sentence)
                        else
                          Text(item.sentence, style: serif(25, height: 1.35)),
                        if (item.translation.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(item.translation, style: sans(14, color: AppColors.ink2)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < item.choices.length; i++) ...[
                    _Option(
                      label: item.choices[i],
                      selected: _selected == i,
                      serifFont: item.skill != Skill.vocabulary && item.skill != Skill.listening,
                      onTap: () => setState(() => _selected = i),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _selected == null
                        ? null
                        : () => _submit(_selected == item.answerIndex ? Answer.correct : Answer.wrong),
                    child: const Text('확인'),
                  ),
                  TextButton(
                    onPressed: () => _submit(Answer.unsure),
                    child: Text(
                      '잘 모르겠어요 (찍지 않기)',
                      style: sans(14, color: AppColors.ink2).copyWith(decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.test, required this.current});
  final AdaptiveTest test;
  final Level current;

  @override
  Widget build(BuildContext context) {
    final steps = [...test.history.map((h) => h.step), current.step];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  test.correctStreak >= 2 ? '연속 ${test.correctStreak}문제 정답! 조금 더 어렵게' : '답에 따라 난이도가 바뀌어요',
                  style: sans(12, color: AppColors.ink2),
                ),
                SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '지금 문제 난이도 ',
                        style: sans(14, weight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: current.cefr.label,
                        style: sans(14, weight: FontWeight.w700, color: AppColors.penBlue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            height: 36,
            child: CustomPaint(
              painter: _TrailPainter(steps: steps, correct: test.history.map((h) => h.isCorrect).toList()),
            ),
          ),
        ],
      ),
    );
  }
}

/// 문항별 난이도 흐름 미니 그래프
class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.steps, required this.correct});
  final List<int> steps;
  final List<bool> correct;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = steps.length > 7 ? steps.sublist(steps.length - 7) : steps;
    final offset = steps.length - shown.length;
    final minS = shown.reduce((a, b) => a < b ? a : b) - 1;
    final maxS = shown.reduce((a, b) => a > b ? a : b) + 1;
    Offset pos(int i) => Offset(
      6 + i * ((size.width - 12) / 6),
      size.height - 6 - (shown[i] - minS) / (maxS - minS) * (size.height - 12),
    );
    final line = Paint()
      ..color = AppColors.lineStrong
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pos(0).dx, pos(0).dy);
    for (var i = 1; i < shown.length; i++) {
      path.lineTo(pos(i).dx, pos(i).dy);
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < shown.length; i++) {
      final isCurrent = i == shown.length - 1;
      final gi = i + offset;
      if (isCurrent) {
        canvas.drawCircle(pos(i), 5, Paint()..color = AppColors.penBlue);
      } else if (correct[gi]) {
        canvas.drawCircle(pos(i), 3.5, Paint()..color = AppColors.success);
      } else {
        canvas.drawCircle(pos(i), 3.5, Paint()..color = AppColors.card);
        canvas.drawCircle(
          pos(i),
          3.5,
          Paint()
            ..color = AppColors.error
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.steps.length != steps.length;
}

class _BlankSentence extends StatelessWidget {
  const _BlankSentence(this.sentence);
  final String sentence;

  @override
  Widget build(BuildContext context) {
    final parts = sentence.split('___');
    final style = serif(25, height: 1.4);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: parts.first),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              width: 110,
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.penBlue, width: 2)),
              ),
              child: Text(' ', style: style),
            ),
          ),
          TextSpan(text: parts.length > 1 ? parts[1] : ''),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap, required this.serifFont});
  final String label;
  final bool selected;
  final bool serifFont;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.penBlueTint : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.penBlue : AppColors.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 54),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: serifFont ? serif(18) : sans(16))),
                  if (selected) Icon(Icons.check_rounded, color: AppColors.penBlue, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
