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
import '../../domain/korean_pron_tips.dart';
import '../../domain/speech_score.dart';
import '../../core/audio/tts.dart';
import 'speech_input.dart';

class SpeakingScreen extends ConsumerStatefulWidget {
  /// [practice] 를 주면 그 문장들만 연습한다 (표현 화면의 '말해보기'). 진행률에는 기록하지 않는다.
  const SpeakingScreen({super.key, this.practice, this.title = '예문 따라 말하기'});

  final List<Sentence>? practice;
  final String title;

  @override
  ConsumerState<SpeakingScreen> createState() => _SpeakingScreenState();
}

class _SpeakingScreenState extends ConsumerState<SpeakingScreen> {
  bool get _practice => widget.practice != null;
  bool get _quiet => ref.read(quietModeProvider);
  List<Sentence> get _sentences => widget.practice ?? ref.read(studyProvider).pack.sentences;

  late int _index = _practice || ref.read(studyProvider).done.contains(RoutineStep.speaking)
      ? 0
      : ref.read(studyProvider).spokenCount.clamp(0, _sentences.length - 1);
  bool _listening = false;
  String _partial = '';
  String? _error;

  /// 연습 모드 결과 (오늘 기록에 넣지 않는다)
  final _practiceResults = <String, SpeechScore>{};

  SpeechScore? _resultFor(StudyState st, Sentence s) => _practice ? _practiceResults[s.id] : st.speaking[s.id];
  bool _done(StudyState st, Sentence s) => _practice ? _practiceResults.containsKey(s.id) : st.hasSpoken(s.id);

  void _record(Sentence s, String heard) {
    if (_practice) {
      setState(() => _practiceResults[s.id] = scoreSpeech(s.en, heard));
    } else {
      ref.read(studyProvider.notifier).recordSpeaking(s, heard);
    }
  }

  Future<void> _toggleMic() async {
    if (_quiet) return;
    final input = ref.read(speechInputProvider);
    if (_listening) {
      await input.stop();
      return;
    }
    final s = _sentences[_index];
    await ref.read(speakerProvider).stop();
    setState(() {
      _listening = true;
      _partial = '';
      _error = null;
    });
    final attempt = await input.listen(
      expected: s.en,
      onPartial: (p) {
        if (mounted) setState(() => _partial = p);
      },
    );
    if (!mounted) return;
    if (attempt.ok) {
      _record(s, attempt.text!);
      HapticFeedback.lightImpact();
    }
    setState(() {
      _listening = false;
      _error = attempt.ok ? null : attempt.error;
    });
  }

  /// 음성 인식을 쓸 수 없을 때: 소리 내어 읽었다고 스스로 체크하고 넘어간다.
  /// 채점하지 않았으므로 말하기 평균에는 넣지 않고 다음 문장으로 넘어간다.
  void _selfCheck() {
    final s = _sentences[_index];
    if (!_practice) ref.read(studyProvider.notifier).recordSilent(s);
    setState(() => _error = null);
    _next(force: true);
  }

  /// 소리 내기 어려운 곳: 듣고 속으로 따라 한 뒤 넘어간다 (점수 없음)
  void _silentNext() {
    final s = _sentences[_index];
    if (!_practice) ref.read(studyProvider.notifier).recordSilent(s);
    _next(force: true);
  }

  void _next({bool force = false}) {
    final st = ref.read(studyProvider);
    if (!force && !_done(st, _sentences[_index])) return;
    if (_index >= _sentences.length - 1) {
      _practice ? context.pop() : finishStep(context, ref, RoutineStep.speaking);
      return;
    }
    setState(() {
      _index++;
      _error = null;
      _partial = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studyProvider);
    ref.watch(quietModeProvider);
    final sentence = _sentences[_index];
    final result = _resultFor(st, sentence);
    final done = _done(st, sentence);
    final say = ref.read(sayProvider);

    return Scaffold(
      body: SafeArea(
        child: StudyShortcuts(
          // iPad 하드웨어 키보드: Space 말하기, S 천천히 듣기, Enter·→ 다음, Esc 닫기
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): () => _quiet ? _silentNext() : _toggleMic(),
            const SingleActivator(LogicalKeyboardKey.keyS): () => say(sentence.en, slow: true),
            const SingleActivator(LogicalKeyboardKey.keyL): () => say(sentence.en),
            const SingleActivator(LogicalKeyboardKey.enter): _next,
            const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
            const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: StudyTopBar(title: widget.title, index: _index, total: _sentences.length),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: Text('소리 내기 어려워요', style: sans(13, weight: FontWeight.w500)),
                        avatar: Icon(_quiet ? Icons.volume_off_rounded : Icons.volume_off_outlined, size: 16),
                        selected: _quiet,
                        showCheckmark: false,
                        selectedColor: AppColors.sand,
                        backgroundColor: AppColors.paper,
                        side: BorderSide(color: AppColors.line),
                        onSelected: (v) => setState(() {
                          ref.read(quietModeProvider.notifier).set(v);
                          _error = null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SentenceView(text: sentence.en, result: result),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(sentence.ko, style: sans(15, color: AppColors.ink2)),
                        ),
                        RoundIconButton(
                          icon: Icons.volume_up_rounded,
                          label: '문장 듣기',
                          filled: false,
                          onPressed: () => say(sentence.en),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_quiet)
                      const _QuietCard()
                    else if (_listening)
                      _HintCard(listening: true, partial: _partial)
                    else if (_error != null)
                      _ErrorCard(message: _error!, onSelfCheck: _selfCheck, onRetry: _toggleMic)
                    else if (result != null) ...[
                      _ScoreCard(result: result),
                      const SizedBox(height: 12),
                      _TipCard(result: result),
                    ] else
                      const _HintCard(listening: false),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: _quiet
                    ? Row(
                        children: [
                          _SideButton(
                            icon: Icons.volume_up_rounded,
                            label: '0.8배',
                            semantic: '천천히 듣기',
                            onTap: () => say(sentence.en, slow: true),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(onPressed: _silentNext, child: const Text('속으로 따라 했어요 · 다음')),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          _SideButton(
                            icon: Icons.volume_up_rounded,
                            label: '0.8배',
                            semantic: '천천히 듣기',
                            onTap: () => say(sentence.en, slow: true),
                          ),
                          const Spacer(),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                button: true,
                                label: _listening ? '말하기 끝내기' : (result == null ? '말하기 시작' : '한 번 더 말하기'),
                                child: GestureDetector(
                                  onTap: _toggleMic,
                                  child: AnimatedContainer(
                                    duration: motion(context, AppMotion.fast),
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      color: _listening ? AppColors.penBlue : AppColors.ink,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: AppColors.sand, spreadRadius: _listening ? 14 : 8)],
                                    ),
                                    child: Icon(
                                      _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                                      size: 32,
                                      color: AppColors.highlighter,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 14),
                              Text(
                                _listening ? '다 말했으면 누르기' : (result == null ? '눌러서 말하기' : '한 번 더 말하기'),
                                style: sans(12, color: AppColors.ink2),
                              ),
                            ],
                          ),
                          Spacer(),
                          _SideButton(
                            icon: Icons.chevron_right_rounded,
                            label: '다음',
                            semantic: '다음 문장',
                            filled: true,
                            onTap: done ? _next : null,
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

/// 소리 내기 어려운 모드 안내
class _QuietCard extends StatelessWidget {
  const _QuietCard();

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      child: Row(
        children: [
          Icon(Icons.hearing_rounded, color: AppColors.penBlue),
          SizedBox(width: 12),
          Expanded(child: Text('이어폰으로 문장을 듣고, 입 모양만 따라 하거나 속으로 따라 해 보세요. 점수는 매기지 않아요.', style: sans(14, height: 1.55))),
        ],
      ),
    );
  }
}

class _SentenceView extends StatelessWidget {
  const _SentenceView({required this.text, this.result});
  final String text;
  final SpeechScore? result;

  @override
  Widget build(BuildContext context) {
    final style = serif(32, weight: 500, height: 1.3, letterSpacing: -0.3);
    final r = result;
    if (r == null) return Text(text, style: style);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final w in r.words)
          Semantics(
            label: w.matched ? w.word : '${w.word}, 다르게 들림',
            excludeSemantics: true,
            child: Container(
              padding: EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: w.matched ? AppColors.success : AppColors.error, width: w.matched ? 2 : 4),
                ),
              ),
              // 색만으로 구분하지 않도록: 다르게 들린 단어에는 표시 아이콘을 붙인다
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(w.word, style: style.copyWith(color: w.matched ? AppColors.ink : AppColors.error)),
                  if (!w.matched) Icon(Icons.hearing_disabled_rounded, size: 16, color: AppColors.error),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.result});
  final SpeechScore result;

  @override
  Widget build(BuildContext context) {
    // 스크린리더가 점수를 바로 읽어 주도록
    return Semantics(
      liveRegion: true,
      label:
          '${result.score}점, ${result.verdict}${result.missed.isEmpty ? '' : '. 다르게 들린 단어: ${result.missed.join(', ')}'}',
      excludeSemantics: true,
      child: _card(),
    );
  }

  Widget _card() {
    return PaperCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: result.score / 100,
                    strokeWidth: 6,
                    backgroundColor: AppColors.muted,
                    color: result.score >= 80 ? AppColors.success : AppColors.ember,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text('${result.score}', style: serif(22, weight: 600)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.verdict, style: sans(15, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '들린 문장: ',
                        style: sans(13, color: AppColors.ink2),
                      ),
                      TextSpan(text: '"${result.heard}"', style: serif(15, italic: true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.result});
  final SpeechScore result;

  @override
  Widget build(BuildContext context) {
    final missed = result.missed;
    final tip = missed.isEmpty
        ? '모든 단어가 또렷하게 들렸어요. 이번엔 조금 더 빠르게, 자연스럽게 말해 볼까요?'
        : '${missed.map((w) => "'$w'").join(', ')} 부분이 다르게 들렸어요. 천천히 듣기로 한 번 더 듣고, 단어를 끊지 말고 덩어리로 이어서 말해 보세요.';
    final pronTips = koreanPronTips(missed);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: AppColors.penBlueTint, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 14, color: AppColors.penBlue),
              const SizedBox(width: 6),
              Text(
                '선생님 한마디',
                style: sans(12, weight: FontWeight.w600, color: AppColors.penBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(tip, style: sans(14, height: 1.6)),
          for (final t in pronTips) ...[
            const SizedBox(height: 6),
            Text('· $t', style: sans(13, height: 1.55, color: AppColors.inkSoft)),
          ],
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.listening, this.partial = ''});
  final bool listening;
  final String partial;

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      child: Row(
        children: [
          Icon(listening ? Icons.hearing_rounded : Icons.record_voice_over_outlined, color: AppColors.penBlue),
          const SizedBox(width: 12),
          Expanded(
            child: listening && partial.isNotEmpty
                ? Text('"$partial"', style: serif(17, italic: true, height: 1.4))
                : Text(
                    listening ? '듣고 있어요. 천천히, 또박또박 말해 보세요.' : '문장을 먼저 듣고, 아래 버튼을 눌러 소리 내어 따라 말해 보세요.',
                    style: sans(14, height: 1.55),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onSelfCheck, required this.onRetry});
  final String message;
  final VoidCallback onSelfCheck;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      color: AppColors.errorTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: sans(14, height: 1.55)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: onRetry, child: const Text('다시 말하기')),
              TextButton(onPressed: onSelfCheck, child: const Text('소리 내어 읽었어요 (넘어가기)')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.semantic,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final String semantic;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: semantic,
      enabled: enabled,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? (enabled ? AppColors.penBlue : AppColors.track) : AppColors.card,
                  border: filled ? null : Border.all(color: AppColors.line),
                ),
                child: Icon(icon, size: 20, color: filled ? AppColors.card : AppColors.penBlue),
              ),
              const SizedBox(height: 4),
              Text(label, style: sans(12, color: enabled ? AppColors.ink : AppColors.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}
