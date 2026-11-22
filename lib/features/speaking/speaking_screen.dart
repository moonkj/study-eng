import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/speech_score.dart';
import '../../core/audio/tts.dart';
import 'speech_input.dart';

class SpeakingScreen extends ConsumerStatefulWidget {
  const SpeakingScreen({super.key});

  @override
  ConsumerState<SpeakingScreen> createState() => _SpeakingScreenState();
}

class _SpeakingScreenState extends ConsumerState<SpeakingScreen> {
  late int _index = ref.read(studyProvider).speaking.length.clamp(0, ref.read(studyProvider).pack.sentences.length - 1);
  bool _listening = false;
  String _partial = '';
  String? _error;

  Future<void> _toggleMic() async {
    final input = ref.read(speechInputProvider);
    if (_listening) {
      await input.stop();
      return;
    }
    final s = ref.read(studyProvider).pack.sentences[_index];
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
      ref.read(studyProvider.notifier).recordSpeaking(s, attempt.text!);
    }
    setState(() {
      _listening = false;
      _error = attempt.ok ? null : attempt.error;
    });
  }

  /// 음성 인식을 쓸 수 없을 때: 소리 내어 읽었다고 스스로 체크하고 넘어간다.
  void _selfCheck() {
    final s = ref.read(studyProvider).pack.sentences[_index];
    ref.read(studyProvider.notifier).recordSpeaking(s, s.en);
    setState(() => _error = null);
  }

  void _next() {
    final total = ref.read(studyProvider).pack.sentences.length;
    if (_index >= total - 1) {
      ref.read(studyProvider.notifier).complete(RoutineStep.speaking);
      context.pop();
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
    final sentence = st.pack.sentences[_index];
    final result = st.speaking[sentence.id];
    final say = ref.read(sayProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: StudyTopBar(title: '예문 따라 말하기', index: _index, total: st.pack.sentences.length),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                children: [
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
                  if (_listening)
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
              child: Row(
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
                            duration: const Duration(milliseconds: 200),
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
                      const SizedBox(height: 14),
                      Text(
                        _listening ? '다 말했으면 누르기' : (result == null ? '눌러서 말하기' : '한 번 더 말하기'),
                        style: sans(12, color: AppColors.ink2),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _SideButton(
                    icon: Icons.chevron_right_rounded,
                    label: '다음',
                    semantic: '다음 문장',
                    filled: true,
                    onTap: result == null ? null : _next,
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
          Container(
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: w.matched ? AppColors.success : AppColors.ember, width: 2.5)),
            ),
            child: Text(w.word, style: style.copyWith(color: w.matched ? AppColors.ink : AppColors.error)),
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
                    backgroundColor: const Color(0xFFEDE6D8),
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
        : '${missed.map((w) => "'$w'").join(', ')} 부분이 다르게 들렸어요. 천천히 듣기로 한 번 더 들은 뒤 따라 해 보세요.';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: AppColors.penBlueTint, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 14, color: AppColors.penBlue),
              const SizedBox(width: 6),
              Text(
                '선생님 한마디',
                style: sans(12, weight: FontWeight.w600, color: AppColors.penBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(tip, style: sans(14, height: 1.6)),
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
