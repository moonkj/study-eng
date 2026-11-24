import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/study_shortcuts.dart';
import '../../core/widgets/widgets.dart';
import '../../data/pack_source.dart';
import '../../domain/speech_score.dart';
import '../../domain/srs.dart';
import '../speaking/speech_input.dart';

/// 간격 반복 복습: 영어를 보고 뜻을 떠올린 뒤 스스로 평가한다. (Claude 호출 없음)
/// 한 번 이상 복습을 통과한 표현은 반대로 한국어 뜻을 보고 영어로 떠올린다 (실제로 말할 수 있어야 하므로).
/// 기본은 속으로 떠올리고 스스로 평가, '말해 보기'를 누르면 음성으로 채점한다.
class ReviewSessionScreen extends ConsumerStatefulWidget {
  const ReviewSessionScreen({super.key});

  @override
  ConsumerState<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends ConsumerState<ReviewSessionScreen> with StudyScreenGuard {
  late final List<LearnedItem> _items = ref.read(studyProvider.notifier).dueReviews();

  /// 처음 세션에 나온 카드 수 (몰라요 카드를 끝에 한 번 더 보여 주기 전)
  late final int _firstPass = _items.length;
  int _index = 0;
  bool _revealed = false;
  final _results = <SelfRating>[];

  /// 한→영으로 묻는 카드 (세션을 열 때 정한다: 평가하면 단계가 바뀌므로)
  late final Set<String> _koToEn = {
    for (final l in _items)
      if (l.kind == 'expression' && (ref.read(studyProvider).cards[l.id]?.stage ?? -1) >= 1) l.id,
  };

  /// 한→영 카드에서 말해 본 점수 (카드 번호별)
  final _spoken = <int, SpeechScore>{};
  bool _listening = false;

  static String _speakable(String pattern) => pattern.replaceAll('~', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> _speak() async {
    if (_listening || _index >= _items.length) return;
    final index = _index;
    final target = _speakable(_items[index].text);
    setState(() => _listening = true);
    final attempt = await ref.read(speechInputProvider).listen(expected: target);
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (attempt.ok && index == _index) {
        _spoken[index] = scoreSpeech(target, attempt.text!);
        _revealed = true; // 말했으면 정답과 비교해 볼 수 있게 바로 보여 준다
      }
    });
  }

  void _rate(SelfRating r) {
    // 뜻을 확인하기 전에는 평가하지 않는다 (키보드로 바로 누르는 경우)
    if (_index >= _items.length || !_revealed) return;
    final item = _items[_index];
    final firstPass = _index < _firstPass;
    if (firstPass) {
      ref.read(studyProvider.notifier).reviewCard(item.id, r);
      _results.add(r);
    }
    HapticFeedback.selectionClick();
    setState(() {
      // 몰랐던 카드는 세션 끝에 한 번 더 본다 (복습 일정은 첫 평가로 이미 정해짐)
      if (firstPass && r == SelfRating.dontKnow) _items.add(item);
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _index >= _items.length;
    return Scaffold(
      body: SafeArea(
        child: StudyShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): () => setState(() => _revealed = true),
            const SingleActivator(LogicalKeyboardKey.digit1): () => _rate(SelfRating.dontKnow),
            const SingleActivator(LogicalKeyboardKey.digit2): () => _rate(SelfRating.confusing),
            const SingleActivator(LogicalKeyboardKey.digit3): () => _rate(SelfRating.know),
            const SingleActivator(LogicalKeyboardKey.escape): () => popOrHome(context),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: StudyTopBar(
                  title: !finished && _index >= _firstPass ? '몰랐던 카드 한 번 더' : '복습',
                  index: _index,
                  total: _items.length,
                  close: true,
                ),
              ),
              Expanded(
                child: _items.isEmpty
                    ? const _Empty()
                    : finished
                    ? _Summary(results: _results)
                    : _Card(
                        koToEn: _koToEn.contains(_items[_index].id),
                        spoken: _spoken[_index],
                        listening: _listening,
                        onSpeak: _speak,
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
                      ? _RatingButtons(onRate: _rate)
                      : FilledButton(
                          onPressed: () => setState(() => _revealed = true),
                          child: Text(_koToEn.contains(_items[_index].id) ? '영어 확인하기' : '뜻 확인하기'),
                        ),
                )
              else
                BottomActions(
                  children: [FilledButton(onPressed: () => popOrHome(context), child: const Text('닫기'))],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 평가 버튼 3개. 글씨를 크게 키운 경우(1.3배 초과)에는 세로로 쌓아 글자가 잘리지 않게 한다.
class _RatingButtons extends StatelessWidget {
  const _RatingButtons({required this.onRate});
  final void Function(SelfRating) onRate;

  @override
  Widget build(BuildContext context) {
    final vertical = MediaQuery.textScalerOf(context).scale(10) > 13;
    final buttons = [
      OutlinedButton(onPressed: () => onRate(SelfRating.dontKnow), child: const Text('몰랐어요')),
      OutlinedButton(onPressed: () => onRate(SelfRating.confusing), child: const Text('헷갈렸어요')),
      FilledButton(onPressed: () => onRate(SelfRating.know), child: const Text('알았어요')),
    ];
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final b in buttons.reversed) Padding(padding: const EdgeInsets.only(bottom: 8), child: b)],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: buttons[i])],
      ],
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
    this.koToEn = false,
    this.spoken,
    this.listening = false,
    this.onSpeak,
  });
  final LearnedItem item;

  /// 한국어 뜻을 보고 영어로 떠올리는 카드
  final bool koToEn;
  final SpeechScore? spoken;
  final bool listening;
  final VoidCallback? onSpeak;
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
        child: LayoutBuilder(
          // 큰 글씨에서 내용이 카드보다 길어지면 스크롤 (평소에는 가운데 정렬 그대로)
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Tag(
                            reviewLabelFor(item, today),
                            color: context.colors.ink,
                            background: context.colors.sand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Spacer(),
                        RoundIconButton(
                          icon: Icons.volume_up_rounded,
                          label: '발음 듣기',
                          filled: false,
                          onPressed: onListen,
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (koToEn) ...[
                      Text(
                        item.meaning,
                        textAlign: TextAlign.center,
                        style: sans(26, weight: FontWeight.w700, height: 1.35, letterSpacing: -0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '영어로 어떻게 말할까요? 속으로 말해 보거나 소리 내어 말해 보세요',
                        textAlign: TextAlign.center,
                        style: sans(13, color: context.colors.ink2),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: listening ? null : onSpeak,
                        icon: Icon(listening ? Icons.hearing_rounded : Icons.mic_none_rounded, size: 18),
                        label: Text(listening ? '듣고 있어요' : (spoken == null ? '말해 보기' : '다시 말해 보기')),
                      ),
                      if (spoken != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${spoken!.score}점 · 들린 문장 "${spoken!.heard}"',
                          textAlign: TextAlign.center,
                          style: sans(
                            13,
                            weight: FontWeight.w600,
                            color: spoken!.score >= 80 ? context.colors.success : context.colors.ember,
                          ),
                        ),
                      ],
                    ] else ...[
                      englishSemantics(
                        item.text,
                        Text(
                          item.text,
                          textAlign: TextAlign.center,
                          style: serif(item.kind == 'word' ? 44 : 32, weight: 500, height: 1.2, letterSpacing: -0.5),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('뜻을 먼저 떠올려 보세요', style: sans(13, color: context.colors.ink2)),
                    ],
                    const Spacer(),
                    const Divider(),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: motion(context, AppMotion.fast),
                      // 뜻이 나타나면 스크린리더가 바로 읽어 준다
                      layoutBuilder: (current, previous) => Semantics(
                        liveRegion: true,
                        // 사라지는 '뜻 보기' 버튼은 읽지 않는다
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final p in previous) ExcludeSemantics(child: p),
                            ?current,
                          ],
                        ),
                      ),
                      child: revealed && koToEn
                          ? englishSemantics(
                              item.text,
                              Text(
                                item.text,
                                key: const ValueKey('english'),
                                textAlign: TextAlign.center,
                                style: serif(28, weight: 500, height: 1.25),
                              ),
                            )
                          : revealed
                          ? Text(
                              item.meaning,
                              key: const ValueKey('meaning'),
                              semanticsLabel: '뜻: ${item.meaning}',
                              textAlign: TextAlign.center,
                              style: sans(20, weight: FontWeight.w700),
                            )
                          : TextButton.icon(
                              key: const ValueKey('hidden'),
                              onPressed: onReveal,
                              icon: const Icon(Icons.visibility_outlined, size: 18),
                              label: Text(koToEn ? '탭해서 영어 보기' : '탭해서 뜻 보기'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
            Icon(Icons.task_alt_rounded, size: 56, color: context.colors.success),
            const SizedBox(height: 16),
            Text('${results.length}장 복습 완료', style: sans(22, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              known == 0
                  ? '오늘 다시 본 것만으로도 기억이 단단해져요. 곧 다시 보여 드릴게요.'
                  : known == results.length
                  ? '모두 기억하고 있었어요. 다음 복습은 더 뒤로 미뤄 둘게요.'
                  : '$known장은 기억하고 있었어요. 헷갈린 카드는 곧 다시 보여 드릴게요.',
              textAlign: TextAlign.center,
              style: sans(14, color: context.colors.ink2, height: 1.5),
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
          style: sans(15, color: context.colors.ink2, height: 1.6),
        ),
      ),
    );
  }
}
