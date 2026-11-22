import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/study_shortcuts.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../speaking/speaking_screen.dart';

class ExpressionScreen extends ConsumerStatefulWidget {
  const ExpressionScreen({super.key});

  @override
  ConsumerState<ExpressionScreen> createState() => _ExpressionScreenState();
}

class _ExpressionScreenState extends ConsumerState<ExpressionScreen> {
  /// 아직 평가하지 않은 첫 표현부터 이어서 연다
  late int _index = () {
    final s = ref.read(studyProvider);
    final i = s.pack.expressions.indexWhere((e) => !s.expressionKnown.containsKey(e.id));
    return i < 0 ? 0 : i;
  }();
  late final _page = PageController(initialPage: _index);

  void _go(int delta) {
    final total = ref.read(studyProvider).pack.expressions.length;
    final target = (_index + delta).clamp(0, total - 1);
    if (target != _index) {
      _page.animateToPage(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  /// 지금 표현의 예문만 따라 말해 보기 (오늘 진행률에는 넣지 않는다)
  void _practice(Expression e) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ColoredBox(
          color: AppColors.paper,
          child: ReadableWidth(
            maxWidth: 680,
            child: SpeakingScreen(
              title: '표현 말해보기',
              practice: [
                for (var i = 0; i < e.examples.length; i++)
                  Sentence(id: '${e.id}-ex$i', en: e.examples[i].en, ko: e.examples[i].ko, focus: e.highlight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _next(int total) {
    if (_index < total - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    } else {
      finishStep(context, ref, RoutineStep.expressions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final items = s.pack.expressions;
    final current = items[_index];
    final known = s.expressionKnown[current.id];
    final isLast = _index == items.length - 1;

    final notifier = ref.read(studyProvider.notifier);
    return Scaffold(
      body: SafeArea(
        // iPad 하드웨어 키보드: ←·→ 이동, 1 이미 알아요, 2 처음 봐요, Enter 다음, Esc 닫기
        child: StudyShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
            const SingleActivator(LogicalKeyboardKey.digit1): () => notifier.setExpressionKnown(current.id, true),
            const SingleActivator(LogicalKeyboardKey.digit2): () => notifier.setExpressionKnown(current.id, false),
            const SingleActivator(LogicalKeyboardKey.enter): () => _next(items.length),
            const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '홈으로',
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.chevron_left_rounded, size: 26),
                    ),
                    const Spacer(),
                    _Dots(count: items.length, index: _index),
                    const Spacer(),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${_index + 1}/${items.length}',
                        textAlign: TextAlign.right,
                        style: sans(13, color: AppColors.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _ExpressionCard(e: items[i]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('이 표현은', style: sans(13, color: AppColors.ink2)),
                    const SizedBox(width: 8),
                    _ChoicePill(
                      label: '이미 알아요',
                      selected: known == true,
                      onTap: () => ref.read(studyProvider.notifier).setExpressionKnown(current.id, true),
                    ),
                    const SizedBox(width: 8),
                    _ChoicePill(
                      label: '처음 봐요',
                      selected: known == false,
                      onTap: () => ref.read(studyProvider.notifier).setExpressionKnown(current.id, false),
                    ),
                  ],
                ),
              ),
              BottomActions(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 10,
                        child: OutlinedButton.icon(
                          onPressed: () => _practice(current),
                          icon: const Icon(Icons.mic_none_rounded, size: 20),
                          label: const Text('말해보기'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 14,
                        child: FilledButton(
                          onPressed: () => _next(items.length),
                          child: Text(isLast ? '표현 학습 완료' : '다음 표현'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpressionCard extends ConsumerWidget {
  const _ExpressionCard({required this.e});
  final Expression e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PaperCard(
      elevated: true,
      radius: AppRadius.sheet,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tag(e.levelLabel),
              const SizedBox(width: 6),
              Tag(e.topic, color: AppColors.ink2, background: const Color(0xFFF1EBDF)),
            ],
          ),
          const SizedBox(height: 18),
          HighlightText(
            e.pattern,
            highlight: e.highlight,
            style: serif(36, weight: 500, height: 1.15, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(e.meaning, style: sans(17, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(e.usage, style: sans(14, color: AppColors.ink2, height: 1.6)),
          const SizedBox(height: 18),
          for (var i = 0; i < e.examples.length; i++)
            ExampleRow(
              en: e.examples[i].en,
              ko: e.examples[i].ko,
              onListen: () => ref.read(sayProvider)(e.examples[i].en),
            ),
          if (e.compare != null) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '헷갈리기 쉬운 표현',
                    style: sans(12, weight: FontWeight.w600, color: AppColors.penBlue),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: e.compare!.$1, style: serif(15)),
                        TextSpan(text: ' ${e.compare!.$2}', style: sans(13, height: 1.55)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count개 중 ${index + 1}번째',
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? AppColors.ink : const Color(0xFFCFC5B2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.ink : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(label, style: sans(13, color: selected ? AppColors.card : AppColors.ink)),
          ),
        ),
      ),
    );
  }
}
