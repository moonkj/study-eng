import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/audio/tts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/study_shortcuts.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// 출퇴근 모드에서 들을 문장 하나 (표현 예문 또는 따라 말하기 문장)
class CommuteItem {
  const CommuteItem(this.en, this.ko, {this.sentence});
  final String en;
  final String ko;

  /// 따라 말하기 문장이면 그 문장 (끝까지 들으면 '속으로 따라 함'으로 기록한다)
  final Sentence? sentence;
}

/// 오늘 팩의 표현 예문 → 따라 말하기 문장 순서. 같은 문장은 한 번만 (표현 문장은 말하기에도 들어 있다).
List<CommuteItem> commuteItems(DailyPack pack) {
  final items = <CommuteItem>[];
  final byText = <String, int>{};
  for (final e in pack.expressions) {
    for (final x in e.examples) {
      if (byText.containsKey(x.en)) continue;
      byText[x.en] = items.length;
      items.add(CommuteItem(x.en, x.ko));
    }
  }
  for (final s in pack.sentences) {
    final i = byText[s.en];
    if (i != null) {
      items[i] = CommuteItem(items[i].en, items[i].ko, sentence: s);
    } else {
      byText[s.en] = items.length;
      items.add(CommuteItem(s.en, s.ko, sentence: s));
    }
  }
  return items;
}

/// 따라 할 시간: 말하는 데 걸릴 시간(단어당 약 0.4초)의 1.2배, 최소 2초
Duration shadowGap(String en, {double speed = 1.0, bool slow = false}) {
  final words = en.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  final spokenMs = (words * 400 + 400) / (speed <= 0 ? 1.0 : speed) / (slow ? 0.8 : 1.0);
  return Duration(milliseconds: math.max(2000, (spokenMs * 1.2).round()));
}

enum _Phase { ready, listen, slow, shadow, done }

/// 출퇴근 모드: 귀로만 듣는 오늘의 문장 (한 손 조작용 큰 버튼)
///
/// 문장마다 영어 듣기 → 한국어 뜻 → 따라 할 빈 시간 → 다음 문장. 끝까지 들으면 말하기 문장을
/// '속으로 따라 함'(점수 없음)으로 기록한다. 말하기 단계를 끝낸 것으로 하지는 않는다.
class CommuteScreen extends ConsumerStatefulWidget {
  const CommuteScreen({super.key});

  @override
  ConsumerState<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends ConsumerState<CommuteScreen> with StudyScreenGuard {
  late final List<CommuteItem> _items = commuteItems(ref.read(studyProvider).pack);
  late final Speaker _speaker;

  int _index = 0;
  bool _playing = false;
  _Phase _phase = _Phase.ready;
  bool _showKo = false;

  /// 천천히(0.8배) 한 번 더 듣기
  bool _slowRepeat = false;

  /// 지금 재생 순서의 번호: 멈추거나 넘기면 바뀌어, 이전 순서의 남은 동작은 그만둔다
  int _run = 0;
  Timer? _gapTimer;
  Completer<void>? _gap;
  Duration _gapLength = Duration.zero;

  /// 따라 할 시간까지 다 들은 말하기 문장
  final _heard = <String, Sentence>{};
  int _recorded = 0;

  @override
  void initState() {
    super.initState();
    _speaker = ref.read(speakerProvider);
  }

  @override
  void dispose() {
    // 화면을 나가면 남은 대기·읽기를 바로 멈춘다 (읽기는 StudyScreenGuard 가 멈춘다)
    _run++;
    _cancelGap();
    super.dispose();
  }

  Future<void> _wait(Duration d) {
    _cancelGap();
    final c = _gap = Completer<void>();
    _gapTimer = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  void _cancelGap() {
    _gapTimer?.cancel();
    _gapTimer = null;
    final c = _gap;
    if (c != null && !c.isCompleted) c.complete();
    _gap = null;
  }

  /// 지금 문장부터 이어서 재생한다
  Future<void> _play() async {
    if (_items.isEmpty) return;
    final run = ++_run;
    bool alive() => mounted && run == _run;
    final say = ref.read(sayProvider);
    setState(() {
      _playing = true;
      if (_phase == _Phase.done) _index = 0;
    });
    while (alive()) {
      final item = _items[_index];
      setState(() {
        _phase = _Phase.listen;
        _showKo = false;
      });
      await say(item.en);
      if (!alive()) return;
      setState(() => _showKo = true);
      if (_slowRepeat) {
        setState(() => _phase = _Phase.slow);
        await say(item.en, slow: true);
        if (!alive()) return;
      }
      final gap = shadowGap(item.en, speed: ref.read(studyProvider).settings.speed, slow: _slowRepeat);
      setState(() {
        _phase = _Phase.shadow;
        _gapLength = gap;
      });
      await _wait(gap);
      if (!alive()) return;
      final s = item.sentence;
      if (s != null) _heard[s.id] = s;
      if (_index >= _items.length - 1) {
        _finish();
        return;
      }
      setState(() => _index++);
    }
  }

  /// 멈춘다 (빈 시간 중이어도 바로)
  void _pause() {
    _run++;
    _cancelGap();
    _speaker.stop();
    setState(() {
      _playing = false;
      if (_phase != _Phase.done) _phase = _Phase.ready;
    });
  }

  void _toggle() => _playing ? _pause() : _play();

  void _jump(int to) {
    if (_items.isEmpty) return;
    if (to >= _items.length) {
      _pause();
      _finish();
      return;
    }
    final wasPlaying = _playing;
    _pause();
    setState(() {
      _index = to.clamp(0, _items.length - 1);
      _showKo = false;
      _phase = _Phase.ready;
    });
    if (wasPlaying) _play();
  }

  /// 끝까지 들었다: 말하기 문장을 '속으로 따라 함'으로 기록 (점수 없음, 단계 완료는 하지 않는다)
  void _finish() {
    final ctrl = ref.read(studyProvider.notifier);
    for (final s in _heard.values) {
      ctrl.recordSilent(s);
    }
    setState(() {
      _recorded = _heard.length;
      _playing = false;
      _phase = _Phase.done;
    });
  }

  String get _phaseLabel => switch (_phase) {
    _Phase.ready => _playing ? '' : '일시 정지',
    _Phase.listen => '듣기',
    _Phase.slow => '천천히 한 번 더',
    _Phase.shadow => '따라 해 보세요',
    _Phase.done => '다 들었어요',
  };

  @override
  Widget build(BuildContext context) {
    final total = _items.length;
    return Scaffold(
      body: SafeArea(
        child: StudyShortcuts(
          // 키보드·이어폰 미디어 키 (기기가 앱으로 보내 주는 경우): 재생/멈춤, 이전, 다음
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space): _toggle,
            const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _toggle,
            const SingleActivator(LogicalKeyboardKey.mediaPlay): () => _playing ? null : _play(),
            const SingleActivator(LogicalKeyboardKey.mediaPause): () => _playing ? _pause() : null,
            const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => _jump(_index + 1),
            const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () => _jump(_index - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _jump(_index + 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _jump(_index - 1),
            const SingleActivator(LogicalKeyboardKey.escape): () => popOrHome(context),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.md, 0),
                child: StudyTopBar(
                  title: '출퇴근 모드 · 귀로 듣기',
                  index: total == 0 ? 0 : (_phase == _Phase.done ? total : _index + 1),
                  total: total,
                  close: true,
                ),
              ),
              Expanded(
                child: _phase == _Phase.done
                    ? _DoneView(recorded: _recorded, onAgain: _play, onClose: () => popOrHome(context))
                    : total == 0
                    ? Center(
                        child: Text('오늘 들을 문장이 없어요.', style: AppType.body(color: context.colors.ink2)),
                      )
                    : _itemView(context, _items[_index]),
              ),
              if (_phase != _Phase.done && total > 0) _controls(context, total),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemView(BuildContext context, CommuteItem item) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xl, AppSpace.xxl, 0),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            _phaseLabel,
            style: AppType.callout(weight: FontWeight.w600, color: context.colors.penBlue, letterSpacing: 0.3),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        englishSemantics(item.en, Text(item.en, style: AppType.enHero(weight: 500, height: 1.3, letterSpacing: -0.3))),
        const SizedBox(height: AppSpace.lg),
        AnimatedOpacity(
          opacity: _showKo || !_playing ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Text(
            item.ko,
            style: AppType.title2(weight: FontWeight.w400, height: 1.5, color: context.colors.ink2),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        if (_phase == _Phase.shadow)
          TweenAnimationBuilder<double>(
            key: ValueKey('gap-$_run-$_index'),
            tween: Tween(begin: 0, end: 1),
            duration: _gapLength,
            builder: (context, v, _) => ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 4,
                color: context.colors.highlighter,
                backgroundColor: context.colors.track,
              ),
            ),
          )
        else
          const SizedBox(height: AppSpace.xs),
        const SizedBox(height: AppSpace.xxl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('천천히 한 번 더 듣기 (0.8배)', style: AppType.body(weight: FontWeight.w500)),
          value: _slowRepeat,
          onChanged: (v) => setState(() => _slowRepeat = v),
        ),
        Text(
          '영어를 듣고, 뜻을 확인하고, 빈 시간에 입 모양이나 속으로 따라 해 보세요. 화면이 켜져 있는 동안 재생돼요.',
          style: AppType.callout(height: 1.55, color: context.colors.ink2),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.sm, AppSpace.xxl, AppSpace.xxl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundControl(
            icon: Icons.skip_previous_rounded,
            label: '이전 문장',
            size: 64,
            onTap: _index > 0 ? () => _jump(_index - 1) : null,
          ),
          _RoundControl(
            icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: _playing ? '일시 정지' : '재생',
            size: 96,
            filled: true,
            onTap: _toggle,
          ),
          _RoundControl(icon: Icons.skip_next_rounded, label: '다음 문장', size: 64, onTap: () => _jump(_index + 1)),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.size,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      excludeSemantics: true,
      child: Material(
        color: filled ? context.colors.ink : context.colors.card,
        shape: CircleBorder(side: filled ? BorderSide.none : BorderSide(color: context.colors.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * 0.45,
              color: filled
                  ? context.colors.highlighter
                  : enabled
                  ? context.colors.penBlue
                  : context.colors.track,
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.recorded, required this.onAgain, required this.onClose});
  final int recorded;
  final VoidCallback onAgain;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xxxl, AppSpace.xxl, AppSpace.xxl),
      children: [
        Icon(Icons.headphones_rounded, size: 40, color: context.colors.penBlue),
        const SizedBox(height: AppSpace.lg),
        Text('오늘 문장을 다 들었어요', style: AppType.title1(weight: FontWeight.w700)),
        const SizedBox(height: AppSpace.sm),
        Text(
          recorded > 0
              ? '말하기 문장 $recorded개를 속으로 따라 한 것으로 기록했어요 (점수 없음). 저녁에 소리 내어 말해 보면 발음 점수를 받을 수 있어요.'
              : '저녁에 소리 내어 말해 보면 발음 점수를 받을 수 있어요.',
          style: AppType.body(height: 1.6, color: context.colors.ink2),
        ),
        const SizedBox(height: AppSpace.xxl),
        FilledButton(onPressed: onClose, child: const Text('홈으로')),
        const SizedBox(height: AppSpace.sm),
        TextButton(onPressed: onAgain, child: const Text('처음부터 다시 듣기')),
      ],
    );
  }
}
