import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/tts.dart';
import '../../core/audio/voice_recorder.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// 녹음은 이 길이까지 (한 문장이면 충분하다)
const kMaxVoiceRecording = Duration(seconds: 8);

enum _Rec { idle, recording, ready }

/// 채점 뒤: 내 목소리를 짧게 녹음해서 듣고, 원어민 읽기와 번갈아 들어 본다.
/// 음성 인식과 따로 녹음한다 (iOS 에서 마이크를 함께 쓰면 충돌해서).
class VoiceCompareCard extends ConsumerStatefulWidget {
  const VoiceCompareCard({super.key, required this.text, required this.sayNative});

  /// 비교할 영어 문장
  final String text;

  /// 원어민 읽기 (다 읽으면 끝나는 Future)
  final Future<void> Function(String text) sayNative;

  @override
  ConsumerState<VoiceCompareCard> createState() => _VoiceCompareCardState();
}

class _VoiceCompareCardState extends ConsumerState<VoiceCompareCard> {
  late final VoiceRecorder _recorder;
  late final Speaker _speaker;

  _Rec _state = _Rec.idle;
  String? _error;
  int _seconds = 0;
  Timer? _ticker;

  /// 재생 중인 것 ('mine' 내 목소리, 'both' 번갈아). 멈추면 번호가 바뀌어 남은 재생을 그만둔다.
  String? _playing;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    // dispose 에서도 쓰므로 미리 받아 둔다 (화면을 떠날 때는 ref 를 쓸 수 없다)
    _recorder = ref.read(voiceRecorderProvider);
    _speaker = ref.read(speakerProvider);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _run++;
    // 화면을 나가거나 다시 말하기를 누르면 녹음·재생을 멈춘다
    _recorder.reset();
    super.dispose();
  }

  Future<void> _start() async {
    await _stopPlayback();
    await _speaker.stop();
    final ok = await _recorder.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = '녹음을 시작하지 못했어요. 마이크 권한을 확인해 주세요.');
      return;
    }
    setState(() {
      _state = _Rec.recording;
      _error = null;
      _seconds = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= kMaxVoiceRecording.inSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _ticker = null;
    final ok = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _state = ok ? _Rec.ready : _Rec.idle;
      _error = ok ? null : '녹음이 저장되지 않았어요. 다시 녹음해 주세요.';
    });
  }

  Future<void> _stopPlayback() async {
    _run++;
    if (_playing != null) {
      await _recorder.stopPlayback();
      await _speaker.stop();
    }
    if (mounted) setState(() => _playing = null);
  }

  Future<void> _playMine() async {
    final run = ++_run;
    setState(() => _playing = 'mine');
    await _recorder.play();
    if (mounted && run == _run) setState(() => _playing = null);
  }

  /// 원어민 → 내 목소리 순서로 듣기
  Future<void> _playBoth() async {
    final run = ++_run;
    setState(() => _playing = 'both');
    await widget.sayNative(widget.text);
    if (!mounted || run != _run) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || run != _run) return;
    await _recorder.play();
    if (mounted && run == _run) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Row(
        children: [
          Icon(Icons.graphic_eq_rounded, size: 16, color: context.colors.penBlue),
          const SizedBox(width: AppSpace.sm),
          Text(
            '내 목소리와 비교',
            style: AppType.callout(weight: FontWeight.w600, color: context.colors.penBlue),
          ),
          const Spacer(),
          if (_state == _Rec.recording)
            Text(
              '녹음 중 $_seconds초 / ${kMaxVoiceRecording.inSeconds}초',
              style: AppType.caption(weight: FontWeight.w600, color: context.colors.error),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.sm),
    ];
    switch (_state) {
      case _Rec.idle:
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
              label: const Text('녹음해서 비교'),
            ),
          ),
        );
      case _Rec.recording:
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('녹음 끝내기'),
            ),
          ),
        );
      case _Rec.ready:
        children.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_playing != null)
                FilledButton.icon(
                  onPressed: _stopPlayback,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('그만 듣기'),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _playMine,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('내 목소리 듣기'),
                ),
                OutlinedButton.icon(
                  onPressed: _playBoth,
                  icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                  label: const Text('원어민과 번갈아 듣기'),
                ),
                TextButton(onPressed: _start, child: const Text('다시 녹음')),
              ],
            ],
          ),
        );
    }
    if (_error != null) {
      children.addAll([
        const SizedBox(height: AppSpace.sm),
        Text(_error!, style: AppType.callout(height: 1.5, color: context.colors.error)),
      ]);
    }
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
