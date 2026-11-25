import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/correct_source.dart';
import '../../data/models.dart';
import '../../data/pack_source.dart' show PackFetchException;

/// 하루에 첨삭받을 수 있는 횟수 (비용 방지). 앱을 다시 켜면 처음부터 센다.
const maxCorrectionsPerDay = 5;

class CorrectionCount extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void add(String day) => state = {...state, day: (state[day] ?? 0) + 1};
}

final correctionCountProvider = NotifierProvider<CorrectionCount, Map<String, int>>(CorrectionCount.new);

/// 표현이 문장에 들어 있는지 ("~" 앞뒤 조각이 순서대로 있으면 들어 있는 것으로 본다)
bool usesExpression(String sentence, String highlight) {
  final s = sentence.toLowerCase().replaceAll('’', "'");
  var from = 0;
  for (final part in highlight.toLowerCase().replaceAll('’', "'").split('~')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final i = s.indexOf(p, from);
    if (i < 0) return false;
    from = i + p.length;
  }
  return true;
}

/// 내 상황으로 말하기: 오늘 표현으로 내 이야기를 한 문장 만들고 첨삭받는다 (배운 표현을 내 것으로 옮기는 연습).
/// 서버가 없으면 표현을 넣었는지만 확인하고 예문과 비교해 보게 한다.
class MySentenceScreen extends ConsumerStatefulWidget {
  const MySentenceScreen({super.key});

  @override
  ConsumerState<MySentenceScreen> createState() => _MySentenceScreenState();
}

class _MySentenceScreenState extends ConsumerState<MySentenceScreen> {
  final _sentence = TextEditingController();
  final _situation = TextEditingController();
  int _expression = 0;
  bool _sending = false;
  Correction? _result;
  String? _error;

  /// 서버 없이 확인한 결과 (표현을 넣었는지)
  bool? _offlineUsed;

  @override
  void dispose() {
    _sentence.dispose();
    _situation.dispose();
    super.dispose();
  }

  Future<void> _submit(Expression e) async {
    final text = _sentence.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    final source = ref.read(correctSourceProvider);
    final s = ref.read(studyProvider);
    final day = s.today.date;
    if (source == null || (ref.read(correctionCountProvider)[day] ?? 0) >= maxCorrectionsPerDay) {
      setState(() {
        _result = null;
        _error = source == null ? null : '오늘 첨삭은 $maxCorrectionsPerDay번까지예요. 예문과 비교해 보세요.';
        _offlineUsed = usesExpression(text, e.highlight);
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _offlineUsed = null;
    });
    try {
      final r = await source.correct(
        expression: (pattern: e.pattern, highlight: e.highlight, meaning: e.meaning),
        situationKo: _situation.text,
        sentence: text,
        level: s.profile.overall.label,
      );
      ref.read(correctionCountProvider.notifier).add(day);
      if (mounted) setState(() => _result = r);
    } on PackFetchException catch (err) {
      if (mounted) setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final expressions = s.pack.expressions;
    if (_expression >= expressions.length) _expression = 0;
    final e = expressions[_expression];
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.xl, 0),
              child: Row(
                children: [
                  IconButton(tooltip: '닫기', onPressed: () => popOrHome(context), icon: const Icon(Icons.close_rounded)),
                  const SizedBox(width: AppSpace.xs),
                  Text('내 상황으로 말하기', style: AppType.headline(weight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.xxl),
                children: [
                  Text('오늘 표현으로 내 이야기를 한 문장 만들어 보세요', style: AppType.body(color: context.colors.ink2)),
                  const SizedBox(height: AppSpace.lg),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < expressions.length; i++)
                        ChoiceChip(
                          label: Text(expressions[i].pattern, style: AppType.enCallout()),
                          selected: i == _expression,
                          onSelected: (_) => setState(() {
                            _expression = i;
                            _result = null;
                            _offlineUsed = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(e.meaning, style: AppType.callout(weight: FontWeight.w600)),
                  const SizedBox(height: AppSpace.lg),
                  TextField(
                    controller: _situation,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '어떤 상황인가요? (선택)', hintText: '예: 회사 동료에게 주말 계획을 말할 때'),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    controller: _sentence,
                    maxLength: 300,
                    minLines: 2,
                    maxLines: 4,
                    autocorrect: false,
                    style: AppType.enBody(),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: '내 문장 (영어)', hintText: e.examples.first.en),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  FilledButton(
                    onPressed: _sentence.text.trim().isEmpty || _sending ? null : () => _submit(e),
                    child: Text(_sending ? '첨삭하는 중…' : (ref.read(correctSourceProvider) == null ? '확인하기' : '첨삭 받기')),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpace.md),
                    Text(_error!, style: AppType.callout(color: context.colors.error)),
                  ],
                  if (_result != null) ...[const SizedBox(height: AppSpace.lg), _ResultCard(result: _result!)],
                  if (_offlineUsed != null) ...[
                    const SizedBox(height: AppSpace.lg),
                    _OfflineCard(used: _offlineUsed!, expression: e),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.result});
  final Correction result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      child: PaperCard(
        color: result.ok ? context.colors.successTint : context.colors.penBlueTint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.ok ? '자연스러운 문장이에요!' : '이렇게 고치면 더 자연스러워요', style: AppType.body(weight: FontWeight.w700)),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(
                  child: englishSemantics(result.corrected, Text(result.corrected, style: AppType.enBody(weight: 500))),
                ),
                RoundIconButton(
                  icon: Icons.volume_up_rounded,
                  label: '문장 듣기',
                  filled: false,
                  onPressed: () => ref.read(sayProvider)(result.corrected),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(result.notes, style: AppType.callout(height: 1.6)),
            if (!result.usedExpression) ...[
              const SizedBox(height: AppSpace.sm),
              Text('오늘 표현을 넣어서 한 번 더 만들어 볼까요?', style: AppType.caption(color: context.colors.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.used, required this.expression});
  final bool used;
  final Expression expression;

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      color: used ? context.colors.successTint : context.colors.errorTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            used ? '오늘 표현을 넣었어요' : "'${expression.highlight}' 가 문장에 없어요",
            style: AppType.body(weight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpace.sm),
          Text('예문과 비교해 보세요', style: AppType.caption(color: context.colors.ink2)),
          for (final x in expression.examples) ...[
            const SizedBox(height: AppSpace.sm),
            HighlightText(
              x.en,
              highlight: expression.highlight.replaceAll('~', '').trim(),
              style: AppType.enCallout(height: 1.4),
            ),
            Text(x.ko, style: AppType.caption(color: context.colors.ink2)),
          ],
        ],
      ),
    );
  }
}
