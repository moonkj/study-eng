import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class _WordsScreenState extends ConsumerState<WordsScreen> {
  late int _index = ref.read(studyProvider).done.contains(RoutineStep.words)
      ? 0
      : ref.read(studyProvider).wordRatings.length.clamp(0, ref.read(studyProvider).pack.words.length - 1);
  bool _revealed = false;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // 화면을 닫은 뒤 '되돌리기'가 남아 다른 화면에서 눌리지 않게
    // dispose 중에는 다른 위젯 상태를 바꾸지 않도록 한 박자 뒤에 숨긴다
    final messenger = _messenger;
    Future.microtask(() {
      if (messenger != null && messenger.mounted) messenger.hideCurrentSnackBar();
    });
    super.dispose();
  }

  void _rate(SelfRating r) {
    final s = ref.read(studyProvider);
    final words = s.pack.words;
    final id = words[_index].id;
    ref.read(studyProvider.notifier).rateWord(id, r);
    HapticFeedback.selectionClick();
    if (_index >= words.length - 1) {
      _messenger?.hideCurrentSnackBar();
      finishStep(context, ref, RoutineStep.words);
      return;
    }
    final rated = _index;
    setState(() {
      _index++;
      _revealed = false;
    });
    // 실수로 누른 평가는 3초 안에 되돌릴 수 있다
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          // 평가 버튼을 가리지 않도록 버튼 위에 띄운다
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 150),
          content: Text('${words[rated].word} → ${_ratingLabel(r)}'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () {
              if (!mounted) return;
              ref.read(studyProvider.notifier).undoWordRating(id);
              if (mounted) setState(() => _index = rated);
            },
          ),
        ),
      );
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
            const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
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
                    duration: const Duration(milliseconds: 280),
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
              Text('이 단어, 얼마나 알고 있었나요?', style: sans(13, color: AppColors.ink2)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _RateButton(
                        label: '몰라요',
                        sub: '내일 다시',
                        color: AppColors.error,
                        onTap: () => _rate(SelfRating.dontKnow),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RateButton(
                        label: '헷갈려요',
                        sub: '3일 뒤',
                        color: AppColors.caution,
                        onTap: () => _rate(SelfRating.confusing),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RateButton(label: '알아요', sub: '7일 뒤', dark: true, onTap: () => _rate(SelfRating.know)),
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
        Positioned(left: 20, right: 20, top: 18, bottom: -14, child: _ghost(const Color(0xFFEDE6D8))),
        Positioned(left: 10, right: 10, top: 9, bottom: -6, child: _ghost(const Color(0xFFF7F2E8))),
        Positioned.fill(
          child: PaperCard(
            elevated: true,
            radius: AppRadius.sheet,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('${word.posKo} · ${word.posEn}', style: sans(12, color: AppColors.ink2)),
                    const Spacer(),
                    Tag(word.levelLabel),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(word.word, style: serif(52, weight: 500, letterSpacing: -1, height: 1)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(word.ipa, style: serif(16, italic: true, color: AppColors.ink2)),
                    const CircleAvatar(radius: 1.5, backgroundColor: AppColors.lineStrong),
                    PronText(word.pronKo, style: sans(14, color: AppColors.ink2)),
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
                  duration: const Duration(milliseconds: 220),
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
                        decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HighlightText(word.example.en, highlight: word.word, style: serif(17, height: 1.4)),
                            const SizedBox(height: 4),
                            Text(word.example.ko, style: sans(13, color: AppColors.ink2)),
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
      ],
    );
  }

  Widget _ghost(Color c) => DecoratedBox(
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      border: Border.all(color: AppColors.line),
    ),
  );
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.label,
    required this.sub,
    required this.onTap,
    this.color = AppColors.ink,
    this.dark = false,
  });
  final String label;
  final String sub;
  final Color color;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? AppColors.ink : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: dark ? BorderSide.none : const BorderSide(color: AppColors.line),
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
                style: sans(15, weight: FontWeight.w600, color: dark ? AppColors.card : color),
              ),
              const SizedBox(height: 2),
              Text(sub, style: sans(12, color: dark ? const Color(0xFFCFC5B2) : AppColors.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}
