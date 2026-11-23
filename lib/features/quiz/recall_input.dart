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
    this.typed,
  });

  final QuizItem item;
  final bool answered;

  /// 답한 뒤 보여 줄 내가 쓴 답
  final String? typed;
  final ValueChanged<String> onSubmit;
  final VoidCallback onGiveUp;

  @override
  State<RecallQuestion> createState() => _RecallQuestionState();
}

class _RecallQuestionState extends State<RecallQuestion> {
  late final _controller = TextEditingController(text: widget.typed ?? '');

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
          padding: const EdgeInsets.all(18),
          child: englishSemantics(
            // 스크린리더에는 빈칸을 '첫 글자 ○로 시작하는 빈칸'처럼 읽히게
            clue.replaceAll(RegExp(r'(\w)_+'), r'$1 빈칸'),
            Text(clue, style: serif(21, height: 1.45, letterSpacing: 0.2)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          enabled: !widget.answered,
          autofocus: !widget.answered,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          keyboardType: TextInputType.visiblePassword, // 자동 완성·자동 대문자 없이 영어 자판으로
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => setState(() {}),
          style: serif(20),
          decoration: InputDecoration(
            labelText: '빈칸에 들어갈 영어',
            hintText: '첫 글자를 보고 떠올려 보세요',
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.ink, width: 1.5),
            ),
          ),
        ),
        if (!widget.answered) ...[
          const SizedBox(height: 14),
          FilledButton(onPressed: _controller.text.trim().isEmpty ? null : _submit, child: const Text('확인')),
          const SizedBox(height: 4),
          TextButton(onPressed: widget.onGiveUp, child: const Text('떠오르지 않아요 · 정답 보기')),
        ],
      ],
    );
  }
}
