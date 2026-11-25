part of 'toeic_task_view.dart';

// 토스 문항의 시간 제한 표시 (P0-7 타이머 접근성)
// 링은 공통 [TimerRing] (emphasizeCaution 으로 남은 5초 굵게·크게). 여기서는 단계 이름 live region,
// 단계 전환 테두리 강조, '곧 끝나요' 글·아이콘만 더한다. 10초·5초 안내와 진동은 화면 상태 쪽에서.

/// 스크린리더로 남은 시간을 따로 알리는 초 (매초 읽지 않는다)
const _announceAt = {10, 5};

/// 남은 시간을 굵게·크게 강조하기 시작하는 초
const _urgentAt = 5;

/// 단계가 바뀔 때 테두리를 잠깐 강조하는 시간
const _flashMotion = Duration(milliseconds: 700);

bool _counting(_Phase p) => p == _Phase.reading || p == _Phase.prep || p == _Phase.speak;

/// 단계 이름 (live region 에는 이것만 넣는다. 초를 넣으면 매초 읽혀 답하는 중 마이크로 들어간다)
(String, String) _phaseNames(_Phase p) => switch (p) {
  _Phase.reading => ('표 읽는 시간', 'Read the information'),
  _Phase.prep => ('준비 시간', 'Begin preparing now'),
  _Phase.speak => ('답하기', 'Begin speaking now'),
  _Phase.finishing => ('정리하는 중', ''),
  _ => ('잘 들어 보세요', ''),
};

/// 남은 시간 안내 문구 (10초·5초에만)
String? _remainingAnnouncement(_Phase phase, int remaining, int total) =>
    _counting(phase) && _announceAt.contains(remaining) && total > remaining ? '$remaining초 남았어요' : null;

/// 원형 링 + 단계 이름.
/// - live region 라벨은 'Q5 답하기' 처럼 단계 이름만 (남은 초는 화면에만, 10초·5초 안내는 화면 쪽에서 따로)
/// - 단계가 바뀌면 링 색·굵기가 [AppMotion.phase] 동안 보간되고, 테두리가 잠깐 강조된다 (동작 줄이기면 생략)
/// - 남은 [_urgentAt] 초부터 링이 굵어지고 숫자가 커지며 '곧 끝나요' 가 붙는다 (색만으로 알리지 않는다)
class _PhaseTimer extends StatefulWidget {
  const _PhaseTimer({required this.phase, required this.remaining, required this.total, required this.number});
  final _Phase phase;
  final int remaining;
  final int total;
  final int number;

  @override
  State<_PhaseTimer> createState() => _PhaseTimerState();
}

class _PhaseTimerState extends State<_PhaseTimer> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this, duration: _flashMotion);

  @override
  void didUpdateWidget(_PhaseTimer old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase && _counting(widget.phase) && !MediaQuery.disableAnimationsOf(context)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.phase;
    final (label, en) = _phaseNames(phase);
    final counting = _counting(phase);
    final urgent = counting && widget.remaining <= _urgentAt;
    final color = phase == _Phase.speak ? context.colors.ember : context.colors.penBlue;
    return Semantics(
      liveRegion: true,
      label: 'Q${widget.number} $label',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _flash,
        builder: (context, child) {
          // 0 → 1 → 0 으로 한 번 깜박이는 테두리
          final t = _flash.isAnimating ? 1 - (2 * _flash.value - 1).abs() : 0.0;
          return Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: color.withValues(alpha: t), width: 2),
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            TimerRing(
              phase: phase == _Phase.speak
                  ? TimerPhase.speak
                  : counting
                  ? TimerPhase.prep
                  : TimerPhase.idle,
              remaining: counting ? widget.remaining : null,
              total: widget.total,
              cautionSeconds: _urgentAt,
              emphasizeCaution: true,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Q${widget.number} · $label', style: AppType.body(weight: FontWeight.w700)),
                  if (en.isNotEmpty) Text(en, style: AppType.enCallout(italic: true, color: context.colors.ink2)),
                  if (urgent)
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 15, color: context.colors.caution),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          '곧 끝나요',
                          style: AppType.callout(weight: FontWeight.w700, color: context.colors.ink),
                        ),
                      ],
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
