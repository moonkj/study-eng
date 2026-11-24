import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/study_shortcuts.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../domain/srs.dart';

class WordsScreen extends ConsumerStatefulWidget {
  const WordsScreen({super.key});

  @override
  ConsumerState<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends ConsumerState<WordsScreen> with StudyScreenGuard {
  late int _index = ref.read(studyProvider).done.contains(RoutineStep.words)
      ? 0
      : ref.read(studyProvider).wordRatings.length.clamp(0, ref.read(studyProvider).pack.words.length - 1);
  bool _revealed = false;

  /// 방금 한 평가 되돌리기 안내 (3초 동안 평가 버튼 위 줄에 보인다. 카드를 가리지 않게 떠 있는 알림 대신)
  ({int index, String id, String text})? _undo;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _clearUndo() {
    _undoTimer?.cancel();
    if (_undo != null) setState(() => _undo = null);
  }

  void _rate(SelfRating r) {
    // 뜻을 확인하기 전에는 평가하지 않는다 (안 보고 '알아요'를 누르면 복습 일정이 실제보다 늦어진다)
    if (!_revealed) return;
    final s = ref.read(studyProvider);
    final words = s.pack.words;
    final id = words[_index].id;
    ref.read(studyProvider.notifier).rateWord(id, r);
    HapticFeedback.selectionClick();
    if (_index >= words.length - 1) {
      _clearUndo();
      finishStep(context, ref, RoutineStep.words);
      return;
    }
    final rated = _index;
    setState(() {
      _index++;
      _revealed = false;
    });
    // 끝낸 단계를 다시 보는 중이면 평가가 반영되지 않으므로 되돌리기 안내도 띄우지 않는다
    if (s.done.contains(RoutineStep.words)) return;
    // 실수로 누른 평가는 3초 안에 되돌릴 수 있다
    _undoTimer?.cancel();
    setState(() => _undo = (index: rated, id: id, text: '${words[rated].word} → ${_ratingLabel(r)}'));
    _undoTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _undo = null);
    });
  }

  void _undoLast() {
    final u = _undo;
    if (u == null) return;
    ref.read(studyProvider.notifier).undoWordRating(u.id);
    _undoTimer?.cancel();
    setState(() {
      _index = u.index;
      _revealed = false;
      _undo = null;
    });
  }

  static String _ratingLabel(SelfRating r) => switch (r) {
    SelfRating.dontKnow => '몰라요 (내일 다시)',
    SelfRating.confusing => '헷갈려요 (3일 뒤)',
    SelfRating.know => '알아요 (7일 뒤)',
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final words = s.pack.words;
    // 팩이 바뀌어 개수가 줄었으면 범위 안으로
    if (_index >= words.length) _index = words.length - 1;
    final w = words[_index];

    return Scaffold(
      body: SafeArea(
        // iPad 하드웨어 키보드: Space 뜻 보기, 1·2·3 평가, L 발음 듣기, Esc 닫기
        child: StudyShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): () => setState(() => _revealed = true),
            const SingleActivator(LogicalKeyboardKey.digit1): () => _rate(SelfRating.dontKnow),
            const SingleActivator(LogicalKeyboardKey.digit2): () => _rate(SelfRating.confusing),
            const SingleActivator(LogicalKeyboardKey.digit3): () => _rate(SelfRating.know),
            const SingleActivator(LogicalKeyboardKey.keyL): () => ref.read(sayProvider)(w.word),
            const SingleActivator(LogicalKeyboardKey.escape): () => popOrHome(context),
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: StudyTopBar(title: '오늘의 단어', index: _index, total: words.length),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: AnimatedSwitcher(
                    duration: motion(context, AppMotion.base),
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween(
                        begin: const Offset(0.15, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: _WordCard(
                      key: ValueKey(w.id),
                      word: w,
                      revealed: _revealed,
                      onReveal: () => setState(() => _revealed = true),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: motion(context, AppMotion.fast),
                child: _undo == null
                    ? Text(
                        _revealed ? '이 단어, 얼마나 알고 있었나요?' : '먼저 뜻을 떠올려 본 뒤, 뜻을 확인하고 평가해요',
                        key: ValueKey(_revealed),
                        style: sans(13, color: context.colors.ink2),
                      )
                    : Semantics(
                        key: ValueKey(_undo),
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _undo!.text,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(13, weight: FontWeight.w600, color: context.colors.ink),
                                ),
                              ),
                              TextButton(
                                onPressed: _undoLast,
                                style: TextButton.styleFrom(foregroundColor: context.colors.penBlue),
                                child: const Text('되돌리기'),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _RateButton(
                        label: '몰라요',
                        sub: '내일 다시',
                        color: context.colors.error,
                        onTap: _revealed ? () => _rate(SelfRating.dontKnow) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RateButton(
                        label: '헷갈려요',
                        sub: '3일 뒤',
                        color: context.colors.caution,
                        onTap: _revealed ? () => _rate(SelfRating.confusing) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RateButton(
                        label: '알아요',
                        sub: '7일 뒤',
                        dark: true,
                        onTap: _revealed ? () => _rate(SelfRating.know) : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordCard extends ConsumerWidget {
  const _WordCard({super.key, required this.word, required this.revealed, required this.onReveal});
  final Word word;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(left: 20, right: 20, top: 18, bottom: -14, child: _ghost(context.colors.muted, context.colors.line)),
        Positioned(
          left: 10,
          right: 10,
          top: 9,
          bottom: -6,
          child: _ghost(context.colors.mutedSoft, context.colors.line),
        ),
        Positioned.fill(
          child: PaperCard(
            elevated: true,
            radius: AppRadius.sheet,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: LayoutBuilder(
              // 큰 글씨에서 뜻·예문이 카드보다 길어지면 스크롤
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text('${word.posKo} · ${word.posEn}', style: sans(12, color: context.colors.ink2)),
                            ),
                            const SizedBox(width: 8),
                            const Spacer(),
                            Tag(word.levelLabel),
                          ],
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: englishSemantics(
                            word.word,
                            Text(word.word, style: serif(52, weight: 500, letterSpacing: -1, height: 1)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            englishSemantics(
                              word.ipa,
                              Text(word.ipa, style: serif(16, italic: true, color: context.colors.ink2)),
                            ),
                            CircleAvatar(radius: 1.5, backgroundColor: context.colors.lineStrong),
                            PronText(word.pronKo, style: sans(14, color: context.colors.ink2)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        RoundIconButton(
                          icon: Icons.volume_up_rounded,
                          label: '발음 듣기',
                          size: 52,
                          onPressed: () => ref.read(sayProvider)(word.word),
                        ),
                        const Spacer(),
                        const Divider(),
                        const SizedBox(height: 16),
                        AnimatedCrossFade(
                          duration: motion(context, AppMotion.fast),
                          crossFadeState: revealed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          firstChild: SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: onReveal,
                              icon: const Icon(Icons.visibility_outlined, size: 18),
                              label: const Text('탭해서 뜻 보기'),
                              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(96)),
                            ),
                          ),
                          secondChild: Column(
                            children: [
                              Text(
                                word.meaning,
                                textAlign: TextAlign.center,
                                style: sans(20, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: context.colors.paper,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    HighlightText(word.example.en, highlight: word.word, style: serif(17, height: 1.4)),
                                    const SizedBox(height: 4),
                                    Text(word.example.ko, style: sans(13, color: context.colors.ink2)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ghost(Color c, Color border) => DecoratedBox(
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      border: Border.all(color: border),
    ),
  );
}

class _RateButton extends StatelessWidget {
  const _RateButton({required this.label, required this.sub, required this.onTap, this.color, this.dark = false});
  final String label;
  final String sub;
  final Color? color;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 뜻을 보기 전(누를 수 없음)에는 흐리게 보인다
    return AnimatedOpacity(
      duration: motion(context, AppMotion.fast),
      opacity: onTap == null ? 0.45 : 1,
      child: Semantics(enabled: onTap != null, button: true, child: _button(context)),
    );
  }

  Widget _button(BuildContext context) {
    return Material(
      color: dark ? context.colors.emphasis : context.colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: dark ? BorderSide.none : BorderSide(color: context.colors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          // 큰 글씨에서도 넘치지 않도록 최소 높이만 정한다
          constraints: const BoxConstraints(minHeight: 64),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: sans(
                  15,
                  weight: FontWeight.w600,
                  color: dark ? context.colors.onEmphasis : (color ?? context.colors.ink),
                ),
              ),
              const SizedBox(height: 2),
              Text(sub, style: sans(12, color: dark ? context.colors.onEmphasisSoft : context.colors.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}
