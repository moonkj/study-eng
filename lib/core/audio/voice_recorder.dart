import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 내 목소리 짧게 녹음해서 다시 듣기 (원어민 발음과 비교용)
///
/// 음성 인식(STT)과 마이크를 같이 쓰면 iOS 에서 서로 충돌하므로, 채점과는 따로 짧게 녹음한다.
abstract class VoiceRecorder {
  /// 녹음을 시작한다. 마이크 권한이 없거나 시작하지 못하면 false.
  Future<bool> start();

  /// 녹음을 끝낸다. 들을 녹음이 있으면 true.
  Future<bool> stop();

  /// 마지막 녹음을 재생하고, 다 들으면(또는 멈추면) 끝난다.
  Future<void> play();

  /// 재생을 멈춘다.
  Future<void> stopPlayback();

  /// 녹음·재생을 모두 멈춘다 (음성 인식을 시작하기 전, 화면을 나갈 때).
  Future<void> reset();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  String? _path;

  /// tts.dart 와 같은 오디오 설정 (일반 재생): playAndRecord 는 통화용 음량 처리로 소리가 작아진다.
  /// 녹음·음성 인식은 시작할 때 각자 마이크 설정으로 바꾼다.
  static final _audioContext = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.allowBluetoothA2DP},
    ),
  );

  @override
  Future<bool> start() async {
    try {
      final rec = _recorder ??= AudioRecorder();
      if (!await rec.hasPermission()) return false;
      await _player?.stop();
      // 웹은 경로를 쓰지 않고 녹음이 끝나면 blob 주소를 돌려준다
      final path = kIsWeb ? '' : '${(await getTemporaryDirectory()).path}/todaye_my_voice.m4a';
      await rec.start(
        const RecordConfig(
          numChannels: 1,
          iosConfig: IosRecordConfig(
            categoryOptions: [
              IosAudioCategoryOption.defaultToSpeaker,
              IosAudioCategoryOption.allowBluetooth,
              IosAudioCategoryOption.allowBluetoothA2DP,
            ],
          ),
        ),
        path: path,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stop() async {
    try {
      final path = await _recorder?.stop();
      if (path != null && path.isNotEmpty) _path = path;
      return path != null && path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> play() async {
    final path = _path;
    if (path == null) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.setAudioContext(_audioContext);
      final done = player.onPlayerStateChanged
          .firstWhere((s) => s == PlayerState.completed || s == PlayerState.stopped)
          .then((_) {}, onError: (_) {});
      await player.play(kIsWeb ? UrlSource(path) : DeviceFileSource(path));
      // 녹음은 8초까지라 넉넉히 기다린다 (완료 알림이 오지 않아도 매달리지 않게)
      await done.timeout(const Duration(seconds: 12), onTimeout: () {});
    } catch (_) {
      // 재생하지 못해도 학습은 계속한다
    }
  }

  @override
  Future<void> stopPlayback() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  Future<void> reset() async {
    try {
      final rec = _recorder;
      if (rec != null && await rec.isRecording()) await rec.stop();
    } catch (_) {}
    await stopPlayback();
  }

  void dispose() {
    _recorder?.dispose();
    _player?.dispose();
  }
}

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final r = DeviceVoiceRecorder();
  ref.onDispose(r.dispose);
  return r;
});
