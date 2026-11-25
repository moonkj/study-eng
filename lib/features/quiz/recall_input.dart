import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// 회상형 문제: 한국어 문장과 첫 글자만 보이는 영어 문장을 보고 빈칸 단어를 직접 쓴다.
/// 보기에서 고르는 것(재인)보다 기억에 오래 남는다.
class RecallQuestion extends StatefulWidget {
  const RecallQuestion({
    super.key,
    required this.item,
    required this.answered,
    required this.onSubmit,
    required this.onGiveUp,
    required this.onSelfGrade,
    this.typed,
  });

  final QuizItem item;
  final bool answered;

  /// 답한 뒤 보여 줄 내가 쓴 답
  final String? typed;
  final ValueChanged<String> onSubmit;
  final VoidCallback onGiveUp;

  /// 쓰기 어려울 때(한 손·지하철): 머릿속으로 떠올린 뒤 정답을 보고 스스로 채점한다. 점수에는 넣지 않는다.
  final ValueChanged<bool> onSelfGrade;

  @override
  State<RecallQuestion> createState() => _RecallQuestionState();
}

class _RecallQuestionState extends State<RecallQuestion> {
  late final _controller = TextEditingController(text: widget.typed ?? '');

  /// '떠올렸어요'를 눌러 정답을 보는 중 (맞음/틀림을 고르기 전)
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.answered || _controller.text.trim().isEmpty) return;
    widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final clue = widget.item.clue!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: englishSemantics(
            // 스크린리더에는 빈칸을 '첫 글자 ○로 시작하는 빈칸'처럼 읽히게
            clue.replaceAll(RegExp(r'(\w)_+'), r'$1 빈칸'),
            Text(clue, style: AppType.enTitle(weight: 400, height: 1.45, letterSpacing: 0.2)),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _controller,
          enabled: !widget.answered && !_checking,
          autofocus: !widget.answered,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          keyboardType: TextInputType.visiblePassword, // 자동 완성·자동 대문자 없이 영어 자판으로
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => setState(() {}),
          style: AppType.enTitle(weight: 400),
          decoration: InputDecoration(
            labelText: '빈칸에 들어갈 영어',
            hintText: '첫 글자를 보고 떠올려 보세요',
            filled: true,
            fillColor: context.colors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.row)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.row),
              borderSide: BorderSide(color: context.colors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.row),
              borderSide: BorderSide(color: context.colors.ink, width: 1.5),
            ),
          ),
        ),
        if (!widget.answered && _checking) ...[
          const SizedBox(height: AppSpace.lg),
          PaperCard(
            color: context.colors.sand,
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '정답',
                  style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
                ),
                const SizedBox(height: AppSpace.xs),
                englishSemantics(
                  widget.item.choices.first,
                  Text(widget.item.choices.first, style: AppType.enTitle(weight: 600)),
                ),
                const SizedBox(height: AppSpace.sm),
                Text('떠올린 답과 같았나요? 스스로 채점한 문제는 점수에 넣지 않아요.', style: AppType.caption(color: context.colors.ink2)),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => widget.onSelfGrade(false), child: const Text('틀렸어요')),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(onPressed: () => widget.onSelfGrade(true), child: const Text('맞았어요')),
              ),
            ],
          ),
        ] else if (!widget.answered) ...[
          const SizedBox(height: AppSpace.lg),
          FilledButton(onPressed: _controller.text.trim().isEmpty ? null : _submit, child: const Text('확인')),
          const SizedBox(height: AppSpace.xs),
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              setState(() => _checking = true);
            },
            child: const Text('쓰기 어려워요 · 떠올리고 정답 보기'),
          ),
          TextButton(onPressed: widget.onGiveUp, child: const Text('떠오르지 않아요 · 정답 보기')),
        ],
      ],
    );
  }
}
