import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'widgets.dart' show ThinProgress;

/// [ActionRow] 의 상태
enum ActionRowState {
  /// 기본: 카드색 면 + 테두리
  normal,

  /// 강조: 지금 할 일 (진한 면, 최소 높이 64)
  emphasis,

  /// 지금 단계 (진한 면 대신 펜 파랑 테두리·번호 원, 부제 아래 진행 막대, 오른쪽 값도 펜 파랑).
  /// 주 버튼이 따로 '다음 할 것'을 맡는 화면(홈 루틴 목록)에서 쓴다.
  current,

  /// 완료: 체크 + 제목 취소선 + '완료'
  done,

  /// 잠김: 누를 수 없음 + 자물쇠 아이콘 + '잠김'
  locked,
}

/// 탭하면 어딘가로 가는 한 줄 (루틴 단계·복습·모의고사·설정 항목 등).
/// 왼쪽(번호 원/체크/아이콘) · 제목(body 15/600) · 부제(caption) · 오른쪽 값 + 화살표.
/// 상태는 색만이 아니라 아이콘·글자(완료/잠김)로도 보인다.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.number,
    this.leading,
    this.value,
    this.trailing,
    this.state = ActionRowState.normal,
    this.progress,
    this.onTap,
    this.tinted = false,
    this.bordered = true,
    this.chevron = true,
  });

  final String title;
  final String? subtitle;

  /// 왼쪽 아이콘 (22). [number] 가 있으면 번호 원이 우선한다.
  final IconData? icon;

  /// 왼쪽 번호 원 (루틴 단계). 완료 상태면 체크로 바뀐다.
  final int? number;

  /// 왼쪽을 직접 그릴 때 (icon·number 보다 우선)
  final Widget? leading;

  /// 오른쪽 짧은 값 ("3분", "이어서")
  final String? value;

  /// 오른쪽을 직접 그릴 때 (value·화살표 대신)
  final Widget? trailing;

  final ActionRowState state;

  /// 0~1. 강조 상태에서 제목 아래 얇은 진행 막대로 보인다 (부제 대신). 지금 단계 상태면 부제 아래 (0보다 클 때만).
  final double? progress;

  final VoidCallback? onTap;

  /// 옅은 파랑 면 (주말 모의고사 권유처럼 살짝 눈에 띄게)
  final bool tinted;

  /// false 면 면·테두리 없이 (설정 묶음 카드 안의 항목)
  final bool bordered;

  /// 누를 수 있을 때 오른쪽 화살표
  final bool chevron;

  /// 최소 높이: 기본 60, 강조 64
  static const minHeight = 60.0;
  static const emphasisMinHeight = 64.0;
  static const iconSize = 22.0;

  /// 묶음 안 구분선 들여쓰기 (아이콘 행의 제목 시작 위치)
  static const dividerIndent = AppSpace.row + iconSize + AppSpace.md;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final emphasis = state == ActionRowState.emphasis;
    final done = state == ActionRowState.done;
    final locked = state == ActionRowState.locked;
    final current = state == ActionRowState.current;
    final fg = emphasis ? c.onEmphasis : (locked ? c.ink2 : c.ink);
    final soft = emphasis ? c.onEmphasisSoft : c.ink2;
    final accent = emphasis ? c.onEmphasisAccent : c.penBlue;

    final Color background = !bordered
        ? Colors.transparent
        : emphasis
        ? c.emphasis
        : done
        ? Colors.transparent
        : locked
        ? c.mutedSoft
        : tinted
        ? c.penBlueTint
        : c.card;
    final BorderSide side = !bordered || emphasis
        ? BorderSide.none
        : current
        ? BorderSide(color: c.penBlue, width: 1.5)
        : BorderSide(color: tinted && !done ? c.penBlueTint : c.line);

    Widget? lead = leading;
    if (lead == null && number != null) {
      lead = done
          ? CircleAvatar(
              radius: 15,
              backgroundColor: c.success,
              child: Icon(Icons.check_rounded, size: 17, color: c.card),
            )
          : Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: emphasis || current ? accent : c.lineStrong,
                  width: emphasis || current ? 2 : 1.5,
                ),
              ),
              child: Text(
                '$number',
                style: AppType.caption(weight: FontWeight.w700, color: emphasis || current ? accent : c.ink2),
              ),
            );
    } else if (lead == null && icon != null) {
      lead = Icon(done ? Icons.check_circle_rounded : icon, size: iconSize, color: done ? c.success : accent);
    }

    final titleStyle = done
        ? AppType.body(
            weight: FontWeight.w600,
            color: c.ink2,
          ).copyWith(decoration: TextDecoration.lineThrough, decorationColor: c.lineStrong)
        : AppType.body(weight: FontWeight.w600, color: fg);

    final showProgress = emphasis && progress != null;
    Widget? right = trailing;
    if (right == null) {
      final label = done ? '완료' : (locked ? '잠김' : value);
      right = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[Icon(Icons.lock_outline_rounded, size: 16, color: soft), const SizedBox(width: AppSpace.xs)],
          if (label != null)
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: emphasis
                    ? AppType.caption(weight: FontWeight.w600, color: fg)
                    : current
                    ? AppType.caption(weight: FontWeight.w600, color: accent)
                    : AppType.caption(color: soft),
              ),
            ),
          if (chevron && onTap != null && !done && !locked)
            Icon(Icons.chevron_right_rounded, color: emphasis ? fg : soft, size: 20),
        ],
      );
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.row), side: side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: locked ? null : onTap,
        child: MergeSemantics(
          child: ConstrainedBox(
            // 큰 글씨에서도 넘치지 않도록 최소 높이 + 세로 여백
            constraints: BoxConstraints(minHeight: emphasis ? emphasisMinHeight : minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.row, vertical: AppSpace.sm),
              child: Row(
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: AppSpace.md)],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: titleStyle),
                        if (showProgress) ...[
                          const SizedBox(height: AppSpace.sm),
                          ThinProgress(progress!, color: accent, track: c.onEmphasis.withValues(alpha: 0.2)),
                        ] else if (subtitle != null && !done)
                          Text(subtitle!, style: AppType.caption(color: soft)),
                        if (current && progress != null && progress! > 0) ...[
                          const SizedBox(height: AppSpace.sm),
                          ThinProgress(progress!, color: accent),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  // 긴 값은 줄바꿈된다 (제목과 폭을 나눠 가져 넘치지 않게)
                  Flexible(child: right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
