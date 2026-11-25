import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/audio/tts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// 주간 시리즈 대화: 같은 인물들이 오늘 표현을 대화 속에서 쓴다. 한 줄씩 듣거나 전체를 이어 듣는다.
class DialogueScreen extends ConsumerStatefulWidget {
  const DialogueScreen({super.key});

  @override
  ConsumerState<DialogueScreen> createState() => _DialogueScreenState();
}

class _DialogueScreenState extends ConsumerState<DialogueScreen> with StudyScreenGuard {
  /// 지금 읽는 줄 (전체 듣기 중)
  int? _playing;

  /// 한국어 뜻을 보여 줄지 (먼저 영어만 듣고 이해해 보게 기본은 가린다)
  bool _showKo = false;

  Future<void> _playAll(SeriesDialogue d) async {
    if (_playing != null) {
      setState(() => _playing = null);
      await ref.read(speakerProvider).stop();
      return;
    }
    for (var i = 0; i < d.lines.length; i++) {
      if (!mounted) return;
      setState(() => _playing = i);
      await ref.read(sayProvider)(d.lines[i].en);
      if (!mounted || _playing != i) return; // 멈췄다
    }
    if (mounted) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final d = s.pack.dialogue;
    final highlights = [for (final e in s.pack.expressions) e.highlight.replaceAll('~', '').trim()];
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
                  Expanded(
                    child: Text(
                      d == null ? '오늘의 대화' : '${d.title} · ${d.episode}화',
                      overflow: TextOverflow.ellipsis,
                      style: AppType.headline(weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: d == null
                  ? Center(
                      child: Text('오늘은 대화가 없어요', style: AppType.callout(color: context.colors.ink2)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.xl),
                      children: [
                        Text('오늘 표현이 대화 속에서 어떻게 쓰이는지 들어 보세요', style: AppType.caption(color: context.colors.ink2)),
                        const SizedBox(height: AppSpace.lg),
                        for (var i = 0; i < d.lines.length; i++)
                          _Line(
                            line: d.lines[i],
                            right: d.cast.isNotEmpty && d.lines[i].speaker != d.cast.first,
                            playing: _playing == i,
                            showKo: _showKo,
                            highlights: highlights,
                            onListen: () => ref.read(sayProvider)(d.lines[i].en),
                          ),
                      ],
                    ),
            ),
            if (d != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _showKo = !_showKo),
                        child: Text(_showKo ? '뜻 가리기' : '뜻 보기'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _playAll(d),
                        icon: Icon(_playing == null ? Icons.play_arrow_rounded : Icons.stop_rounded),
                        label: Text(_playing == null ? '전체 듣기' : '멈추기'),
                      ),
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

class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.right,
    required this.playing,
    required this.showKo,
    required this.highlights,
    required this.onListen,
  });
  final DialogueLine line;
  final bool right;
  final bool playing;
  final bool showKo;
  final List<String> highlights;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final hl = highlights.where((h) => h.isNotEmpty && line.en.toLowerCase().contains(h.toLowerCase())).firstOrNull;
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Column(
            crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                line.speaker,
                style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
              ),
              const SizedBox(height: AppSpace.xs),
              Material(
                color: playing ? context.colors.penBlueTint : (right ? context.colors.sand : context.colors.card),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  side: BorderSide(color: playing ? context.colors.penBlue : context.colors.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  onTap: onListen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        hl == null
                            ? englishSemantics(line.en, Text(line.en, style: AppType.enBody(height: 1.4)))
                            : HighlightText(line.en, highlight: hl, style: AppType.enBody(height: 1.4)),
                        if (showKo) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(line.ko, style: AppType.caption(color: context.colors.ink2)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
