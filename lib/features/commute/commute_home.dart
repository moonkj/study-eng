import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../speaking/speaking_screen.dart';

/// 저녁 소리 내기 카드는 이 시각부터 보인다
const kEveningHour = 17;

/// 오늘 속으로만 따라 한 말하기 문장 (저녁에만: 출퇴근길에 들은 문장을 집에서 소리 내어 말해 보게)
List<Sentence> eveningSilentSentences(StudyState s, DateTime now) => now.hour < kEveningHour
    ? const []
    : [
        for (final x in s.pack.sentences)
          if (s.today.spoken[x.id] == kSilentAttempt) x,
      ];

/// 홈 루틴 아래: 저녁 소리 내기 카드 + 출퇴근 모드 버튼
class CommuteEntry extends ConsumerWidget {
  const CommuteEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final now = ref.watch(clockProvider)();
    final silent = eveningSilentSentences(s, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (silent.isNotEmpty) ...[_EveningSpeakCard(sentences: silent), const SizedBox(height: 8)],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push('/commute'),
            icon: const Icon(Icons.headphones_rounded, size: 18),
            label: const Text('출퇴근 모드 · 귀로 듣기'),
            // 루틴 목록 아래 한 줄로 작게 (홈 아래 레벨 카드를 밀어내지 않게)
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ],
    );
  }
}

class _EveningSpeakCard extends StatelessWidget {
  const _EveningSpeakCard({required this.sentences});
  final List<Sentence> sentences;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ColoredBox(
          color: context.colors.paper,
          child: ReadableWidth(
            maxWidth: 680,
            child: SpeakingScreen(practice: sentences, title: '소리 내어 말하기', recordToday: true),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.penBlueTint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.record_voice_over_outlined, color: context.colors.penBlue, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '속으로 따라 한 문장 ${sentences.length}개, 소리 내어 말해 볼까요?',
                    style: sans(15, weight: FontWeight.w500, height: 1.4),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.colors.ink2, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
