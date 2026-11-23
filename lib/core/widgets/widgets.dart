import 'package:flutter/semantics.dart' show AttributedString, LocaleStringAttribute;
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 종이 카드
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.xl),
    this.radius = AppRadius.card,
    this.elevated = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool elevated;

  /// 비우면 카드색
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.line),
        boxShadow: elevated ? AppShadow.card(c) : null,
      ),
      child: child,
    );
  }
}

/// 영어 문장에서 [highlight] 부분에 형광펜을 칠한다.
/// 영어 문장을 스크린리더가 영어 음성으로 읽도록 언어를 표시한다 (한국어 음성으로 읽으면 알아듣기 어렵다).
Widget englishSemantics(String text, Widget child) => Semantics(
  attributedLabel: AttributedString(
    text,
    attributes: [
      LocaleStringAttribute(
        range: TextRange(start: 0, end: text.length),
        locale: const Locale('en', 'US'),
      ),
    ],
  ),
  excludeSemantics: true,
  child: child,
);

class HighlightText extends StatelessWidget {
  const HighlightText(this.text, {super.key, this.highlight, required this.style, this.maxLines});

  final String text;
  final String? highlight;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final h = highlight;
    final idx = h == null ? -1 : text.toLowerCase().indexOf(h.toLowerCase());
    if (h == null || idx < 0) {
      return englishSemantics(text, Text(text, style: style, maxLines: maxLines));
    }
    // 줄 높이 단위로 반복되는 그라디언트로 글자 아래쪽 45%만 형광펜을 칠한다.
    final lineHeight = (style.fontSize ?? 16) * (style.height ?? 1.2);
    // RepaintBoundary: 형광펜 셰이더 좌표가 이 글자 위치를 기준으로 반복되게 (없으면 띠가 위아래로 어긋난다)
    return englishSemantics(
      text,
      RepaintBoundary(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text.substring(0, idx)),
              TextSpan(
                text: text.substring(idx, idx + h.length),
                style: style.copyWith(
                  background: Paint()
                    ..shader = LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.55, 0.55, 0.95, 0.95],
                      colors: [
                        context.colors.highlighter.withValues(alpha: 0),
                        context.colors.highlighter,
                        context.colors.highlighter,
                        context.colors.highlighter.withValues(alpha: 0),
                      ],
                      tileMode: TileMode.repeated,
                    ).createShader(Rect.fromLTWH(0, 0, 10, lineHeight)),
                ),
              ),
              TextSpan(text: text.substring(idx + h.length)),
            ],
          ),
          style: style,
          maxLines: maxLines,
        ),
      ),
    );
  }
}

/// 작은 라벨 칩
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.background, this.icon});

  final String label;

  /// 비우면 펜 파랑 / 옅은 파랑 배경
  final Color? color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.colors.penBlue;
    final background = this.background ?? context.colors.penBlueTint;
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(13)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              style: sans(12, weight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 얇은 진행 바
class ThinProgress extends StatelessWidget {
  const ThinProgress(this.value, {super.key, this.height = 4, this.color, this.track});

  final double value;
  final double height;

  /// 비우면 잉크 / 트랙색
  final Color? color;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.colors.ink;
    final track = this.track ?? context.colors.track;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        // 폭을 꽉 채워야 빈 트랙이 끝까지 그려진다 (Stack 은 채워진 부분 크기로 줄어든다)
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              widthFactor: value.clamp(0, 1),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// 동그란 아이콘 버튼 (듣기 등). 터치 영역 최소 44.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? context.colors.penBlue : context.colors.paper,
        shape: CircleBorder(side: filled ? BorderSide.none : BorderSide(color: context.colors.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.42, color: filled ? context.colors.card : context.colors.penBlue),
          ),
        ),
      ),
    );
  }
}

/// 학습 화면 상단: 뒤로/닫기 + 진행률 + 개수
class StudyTopBar extends StatelessWidget {
  const StudyTopBar({
    super.key,
    required this.title,
    required this.index,
    required this.total,
    this.close = false,
    this.trailing,
  });

  final String title;
  final int index;
  final int total;
  final bool close;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: close ? '닫기' : '홈으로',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: Icon(close ? Icons.close_rounded : Icons.chevron_left_rounded, size: 26),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            // 스크린리더: '오늘의 단어, 10개 중 3개 완료'
            label: '$title, $total개 중 $index개 완료',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sans(15, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                ThinProgress(total == 0 ? 0 : index / total),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        ExcludeSemantics(
          child: Text(
            '$index/$total',
            style: sans(13, weight: FontWeight.w600, color: context.colors.ink2),
          ),
        ),
        if (trailing != null) trailing! else const SizedBox(width: 8),
      ],
    );
  }
}

/// 예문 한 줄 (영어 세리프 + 한국어 번역 + 듣기 버튼)
class ExampleRow extends StatelessWidget {
  const ExampleRow({super.key, required this.en, required this.ko, this.onListen, this.divider = true});

  final String en;
  final String ko;
  final VoidCallback? onListen;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: divider
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.line, style: BorderStyle.solid),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                englishSemantics(en, Text(en, style: serif(18, height: 1.35))),
                const SizedBox(height: 3),
                Text(ko, style: sans(13, color: context.colors.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RoundIconButton(icon: Icons.volume_up_rounded, label: '예문 듣기', filled: false, onPressed: onListen),
        ],
      ),
    );
  }
}

/// 화면 하단 고정 버튼 영역
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// 한글 발음 표기. [대괄호] 로 표시한 강세 음절을 굵고 진하게 보여준다. 예: "[액]슈얼리"
class PronText extends StatelessWidget {
  const PronText(this.pron, {super.key, required this.style});
  final String pron;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\[([^\]]+)\]');
    var last = 0;
    for (final m in re.allMatches(pron)) {
      if (m.start > last) spans.add(TextSpan(text: pron.substring(last, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.ink),
        ),
      );
      last = m.end;
    }
    if (last < pron.length) spans.add(TextSpan(text: pron.substring(last)));
    final plain = pron.replaceAll('[', '').replaceAll(']', '');
    return Semantics(
      label: '발음 $plain',
      excludeSemantics: true,
      child: Text.rich(TextSpan(style: style, children: spans)),
    );
  }
}
