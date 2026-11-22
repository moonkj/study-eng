import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/pack_source.dart';
import '../../domain/srs.dart';

/// 간격 반복 복습: 영어를 보고 뜻을 떠올린 뒤 스스로 평가한다. (Claude 호출 없음)
class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> {
  late final List<LearnedItem> _items = ref.read(studyProvider.notifier).dueReviews();
  int _index = 0;
  bool _revealed = false;
  final _results = <SelfRating>[];

  void _rate(SelfRating r) {
    if (_index >= _items.length) return;
    ref.read(studyProvider.notifier).reviewCard(_items[_index].id, r);
    HapticFeedback.selectionClick();
    setState(() {
      _results.add(r);
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _index >= _items.length;
    return Scaffold(
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): () => setState(() => _revealed = true),
            const SingleActivator(LogicalKeyboardKey.digit1): () => _rate(SelfRating.dontKnow),
            const SingleActivator(LogicalKeyboardKey.digit2): () => _rate(SelfRating.confusing),
            const SingleActivator(LogicalKeyboardKey.digit3): () => _rate(SelfRating.know),
            const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                  child: StudyTopBar(title: '복습', index: _index, total: _items.length, close: true),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const _Empty()
                      : finished
                      ? _Summary(results: _results)
                      : _Card(
                          item: _items[_index],
                          today: ref.read(studyProvider).now,
                          revealed: _revealed,
                          onReveal: () => setState(() => _revealed = true),
                          onListen: () => ref.read(sayProvider)(_items[_index].text.replaceAll('~', '')),
                        ),
                ),
                if (!finished && _items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _revealed
                        ? Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _rate(SelfRating.dontKnow),
                                  child: const Text('몰랐어요'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _rate(SelfRating.confusing),
                                  child: const Text('헷갈렸어요'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(onPressed: () => _rate(SelfRating.know), child: const Text('알았어요')),
                              ),
                            ],
                          )
                        : FilledButton(onPressed: () => setState(() => _revealed = true), child: const Text('뜻 확인하기')),
                  )
                else
                  BottomActions(
                    children: [FilledButton(onPressed: () => context.pop(), child: const Text('닫기'))],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.today,
    required this.revealed,
    required this.onReveal,
    required this.onListen,
  });
  final LearnedItem item;
  final DateTime today;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: PaperCard(
        elevated: true,
        radius: AppRadius.sheet,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          children: [
            Row(
              children: [
                Tag(reviewLabelFor(item, today), color: AppColors.ink, background: AppColors.sand),
                const Spacer(),
                RoundIconButton(icon: Icons.volume_up_rounded, label: '발음 듣기', filled: false, onPressed: onListen),
              ],
            ),
            const Spacer(),
            Text(
              item.text,
              textAlign: TextAlign.center,
              style: serif(item.kind == 'word' ? 44 : 32, weight: 500, height: 1.2, letterSpacing: -0.5),
            ),
            const SizedBox(height: 12),
            Text('뜻을 먼저 떠올려 보세요', style: sans(13, color: AppColors.ink2)),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: revealed
                  ? Text(
                      item.meaning,
                      key: const ValueKey('meaning'),
                      textAlign: TextAlign.center,
                      style: sans(20, weight: FontWeight.w700),
                    )
                  : TextButton.icon(
                      key: const ValueKey('hidden'),
                      onPressed: onReveal,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('탭해서 뜻 보기'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.results});
  final List<SelfRating> results;

  @override
  Widget build(BuildContext context) {
    final known = results.where((r) => r == SelfRating.know).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.task_alt_rounded, size: 56, color: AppColors.success),
            const SizedBox(height: 16),
            Text('${results.length}장 복습 완료', style: sans(22, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '$known장은 기억하고 있었어요. 헷갈린 카드는 곧 다시 보여 드릴게요.',
              textAlign: TextAlign.center,
              style: sans(14, color: AppColors.ink2, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          '오늘 복습할 카드가 없어요.\n잊어버릴 때쯤 다시 보여 드릴게요.',
          textAlign: TextAlign.center,
          style: sans(15, color: AppColors.ink2, height: 1.6),
        ),
      ),
    );
  }
}
