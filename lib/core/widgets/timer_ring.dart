import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// [TimerRing] 단계: 대기(숫자 없음·돌기만) / 준비(펜 파랑) / 답하기(불씨색)
enum TimerPhase { idle, prep, speak }

/// 토스 원형 타이머. 크기 64(기본) / 32(상단 미니) / 96(iPad).
/// 준비→답하기로 바뀌면 색(timerPrep→timerSpeak)과 굵기(5→7, 64 기준)를 240ms 동안 보간한다 (동작 줄이기면 즉시).
/// 남은 [cautionSeconds]초 이하면 숫자를 caution 색으로 (숫자 자체가 정보라 색만으로 읽지 않는다).
/// 링 자체는 스크린리더에서 숨긴다: 단계 이름은 [semanticsLabel] 로 live region 에 한 번만 알린다
/// (매초 읽히면 답하는 중 스크린리더 소리가 마이크로 들어간다).
class TimerRing extends StatelessWidget {
  const TimerRing({
    super.key,
    required this.phase,
    this.remaining,
    this.total,
    this.size = 64,
    this.cautionSeconds = 5,
    this.semanticsLabel,
  });

  final TimerPhase phase;

  /// 남은 초. null 이면 숫자 없이 돌기만 한다.
  final int? remaining;

  /// 전체 초 (진행 비율 계산용)
  final int? total;

  final double size;
  final int cautionSeconds;

  /// 있으면 live region 으로 알린다 (예: "Q5 답하기")
  final String? semanticsLabel;

  static const mini = 32.0;
  static const regular = 64.0;
  static const large = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = remaining;
    final t = total;
    final counting = phase != TimerPhase.idle && r != null;
    final value = counting && t != null && t > 0 ? (r / t).clamp(0.0, 1.0) : null;
    final caution = counting && r <= cautionSeconds;
    final baseStroke = size * 5 / 64;
    final numberStyle = size >= large
        ? AppType.enHero(weight: 600)
        : size >= regular
        ? AppType.enTitle(weight: 600)
        : AppType.enCaption(weight: 600);

    final ring = TweenAnimationBuilder<double>(
      tween: Tween(end: phase == TimerPhase.speak ? 1 : 0),
      duration: motion(context, AppMotion.phase),
      curve: AppMotion.curve,
      builder: (context, k, _) => SizedBox.expand(
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: baseStroke * (1 + 0.4 * k),
          backgroundColor: c.muted,
          color: Color.lerp(c.timerPrep, c.timerSpeak, k),
          strokeCap: StrokeCap.round,
        ),
      ),
    );

    final body = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ring,
          if (counting)
            Padding(
              padding: EdgeInsets.all(baseStroke * 1.6),
              // 큰 글씨 설정에서도 링 밖으로 넘치지 않게
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$r', style: numberStyle.copyWith(color: caution ? c.caution : null)),
              ),
            ),
        ],
      ),
    );

    if (semanticsLabel == null) return ExcludeSemantics(child: body);
    return Semantics(liveRegion: true, label: semanticsLabel, excludeSemantics: true, child: body);
  }
}
