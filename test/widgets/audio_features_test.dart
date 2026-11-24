import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/app.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/audio/tts.dart';
import 'package:todaye/core/audio/voice_recorder.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/sample_content.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/pack_prep.dart';
import 'package:todaye/features/commute/commute_home.dart';
import 'package:todaye/features/commute/commute_screen.dart';
import 'package:todaye/features/speaking/speech_input.dart';

import '../domain/reminder_test.dart' show FakeReminder;
import 'daily_flow_test.dart' show FakeSpeaker, seeded, setPhone;

class _PerfectSpeech implements SpeechInput {
  @override
  Future<SpeechAttempt> listen({
    required String expected,
    bool hint = false,
    void Function(String partial)? onPartial,
  }) async => SpeechAttempt.heard(expected);

  @override
  Future<void> stop() async {}
}

class FakeRecorder implements VoiceRecorder {
  FakeRecorder({this.allowed = true});
  final bool allowed;
  var started = 0;
  var stopped = 0;
  var plays = 0;
  var resets = 0;

  @override
  Future<bool> start() async {
    if (allowed) started++;
    return allowed;
  }

  @override
  Future<bool> stop() async {
    stopped++;
    return true;
  }

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> reset() async => resets++;
}

Widget _app({String initial = '/', int hour = 8, FakeSpeaker? speaker, VoiceRecorder? recorder}) => ProviderScope(
  overrides: [
    reminderProvider.overrideWithValue(FakeReminder()),
    speakerProvider.overrideWithValue(speaker ?? FakeSpeaker()),
    storeProvider.overrideWithValue(MemoryStore(seeded())),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, hour, 0)),
    speechInputProvider.overrideWithValue(_PerfectSpeech()),
    voiceRecorderProvider.overrideWithValue(recorder ?? FakeRecorder()),
  ],
  child: TodayeApp(initialLocation: initial),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

/// 목록 가운데로 스크롤 (아래 탭 바·버튼에 가리지 않게)
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  group('출퇴근 모드', () {
    test('표현 예문과 말하기 문장을 겹치지 않게 모으고, 따라 할 시간은 문장 길이에 맞춘다', () {
      final pack = prepareDailyPack(samplePackFor(DateTime(2026, 11, 22), 7), dayNumber: 10);
      final items = commuteItems(pack);
      expect(items.map((i) => i.en).toSet().length, items.length);
      for (final s in pack.sentences) {
        expect(items.where((i) => i.sentence?.id == s.id), hasLength(1));
      }
      expect(shadowGap('Hi.'), const Duration(seconds: 2));
      final long = shadowGap("I've been meaning to call you about the trip next weekend.");
      expect(long, greaterThan(const Duration(seconds: 2)));
      expect(shadowGap("I've been meaning to call you about the trip next weekend.", slow: true), greaterThan(long));
    });

    testWidgets('재생하면 영어 → 따라 할 시간 → 다음 문장으로 넘어가고, 빈 시간 중에 멈출 수 있다', (tester) async {
      await setPhone(tester);
      final speaker = FakeSpeaker();
      await tester.pumpWidget(_app(initial: '/commute', speaker: speaker));
      await tester.pumpAndSettle();
      final items = commuteItems(_container(tester).read(studyProvider).pack);
      expect(find.text('1/${items.length}'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('재생'));
      await tester.pump();
      await tester.pump();
      expect(speaker.spoken, [(items[0].en, false)]);
      expect(find.text('따라 해 보세요'), findsOneWidget);
      expect(find.text(items[0].ko), findsOneWidget);

      // 따라 할 시간이 지나면 다음 문장
      await tester.pump(shadowGap(items[0].en));
      await tester.pump();
      expect(find.text('2/${items.length}'), findsOneWidget);
      expect(speaker.spoken.last, (items[1].en, false));

      // 빈 시간 중에 멈추면 더 넘어가지 않는다
      await tester.tap(find.bySemanticsLabel('일시 정지'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('2/${items.length}'), findsOneWidget);
      expect(speaker.spoken, hasLength(2));

      // 다음 버튼은 멈춘 채로 넘기기만 한다
      await tester.tap(find.bySemanticsLabel('다음 문장'));
      await tester.pump();
      expect(find.text('3/${items.length}'), findsOneWidget);
      expect(speaker.spoken, hasLength(2));
    });

    testWidgets('천천히 한 번 더 켜면 0.8배로 한 번 더 읽는다', (tester) async {
      await setPhone(tester);
      final speaker = FakeSpeaker();
      await tester.pumpWidget(_app(initial: '/commute', speaker: speaker));
      await tester.pumpAndSettle();
      final first = commuteItems(_container(tester).read(studyProvider).pack).first.en;
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('재생'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(speaker.spoken, [(first, false), (first, true)]);
      await tester.tap(find.bySemanticsLabel('일시 정지'));
      await tester.pump();
    });

    testWidgets('끝까지 들으면 말하기 문장을 속으로 따라 한 것으로 기록하지만 단계를 끝내지는 않는다', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(_app(initial: '/commute'));
      await tester.pumpAndSettle();
      final st = _container(tester).read(studyProvider);
      final items = commuteItems(st.pack);

      await tester.tap(find.bySemanticsLabel('재생'));
      for (var i = 0; i < items.length; i++) {
        await tester.pump();
        await tester.pump();
        await tester.pump(shadowGap(items[i].en));
      }
      await tester.pump();
      expect(find.text('오늘 문장을 다 들었어요'), findsOneWidget);

      final after = _container(tester).read(studyProvider);
      for (final s in after.pack.sentences) {
        expect(after.today.spoken[s.id], kSilentAttempt);
      }
      expect(after.done.contains(RoutineStep.speaking), isFalse);
      expect(after.speaking, isEmpty); // 점수는 없다
    });

    testWidgets('화면을 나가면 읽기와 대기가 멈춘다', (tester) async {
      await setPhone(tester);
      final speaker = FakeSpeaker();
      await tester.pumpWidget(_app(initial: '/commute', speaker: speaker));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('재생'));
      await tester.pump();
      await tester.pump();
      expect(speaker.spoken, hasLength(1));

      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(CommuteScreen), findsNothing);
      await tester.pump(const Duration(seconds: 60));
      expect(speaker.spoken, hasLength(1));
      // 끝까지 듣지 않았으니 기록하지 않는다
      expect(_container(tester).read(studyProvider).today.spoken, isEmpty);
    });

    testWidgets('홈의 출퇴근 모드 버튼으로 들어간다', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('출퇴근 모드 · 귀로 듣기'));
      await tester.tap(find.text('출퇴근 모드 · 귀로 듣기'));
      await tester.pumpAndSettle();
      expect(find.byType(CommuteScreen), findsOneWidget);
    });
  });

  group('저녁 소리 내기 카드', () {
    testWidgets('17시 전에는 보이지 않는다', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(_app(hour: 16));
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(studyProvider.notifier).recordSilent(c.read(studyProvider).pack.sentences.first);
      await tester.pumpAndSettle();
      expect(find.textContaining('속으로 따라 한 문장'), findsNothing);
    });

    testWidgets('저녁에 속으로만 따라 한 문장이 없으면 보이지 않는다', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(_app(hour: 19));
      await tester.pumpAndSettle();
      expect(find.textContaining('속으로 따라 한 문장'), findsNothing);
      final s = _container(tester).read(studyProvider);
      expect(eveningSilentSentences(s, DateTime(2026, 11, 22, 19)), isEmpty);
    });

    testWidgets('저녁에는 카드가 보이고, 소리 내어 말하면 속으로 따라 한 표시가 점수로 바뀐다', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(_app(hour: 18));
      await tester.pumpAndSettle();
      final c = _container(tester);
      final sentences = c.read(studyProvider).pack.sentences;
      c.read(studyProvider.notifier)
        ..recordSilent(sentences[0])
        ..recordSilent(sentences[1]);
      await tester.pumpAndSettle();
      final card = find.text('속으로 따라 한 문장 2개, 소리 내어 말해 볼까요?');
      await _reveal(tester, card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('소리 내어 말하기'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('말하기 시작'));
      await tester.pumpAndSettle();
      final st = c.read(studyProvider);
      expect(st.today.spoken[sentences[0].id], sentences[0].en);
      expect(st.speaking[sentences[0].id]?.score, 100);
      expect(st.today.spoken[sentences[1].id], kSilentAttempt);
      expect(eveningSilentSentences(st, DateTime(2026, 11, 22, 18)), [sentences[1]]);
    });
  });

  group('내 목소리 녹음·비교', () {
    Future<FakeSpeaker> scored(WidgetTester tester, FakeRecorder recorder) async {
      await setPhone(tester);
      final speaker = FakeSpeaker();
      await tester.pumpWidget(_app(initial: '/speaking', speaker: speaker, recorder: recorder));
      await tester.pumpAndSettle();
      expect(find.text('녹음해서 비교'), findsNothing); // 채점 전에는 없다
      await tester.tap(find.bySemanticsLabel('말하기 시작'));
      await tester.pumpAndSettle();
      expect(recorder.resets, greaterThan(0)); // 음성 인식 전에 녹음 마이크를 놓는다
      await _reveal(tester, find.text('녹음해서 비교'));
      return speaker;
    }

    testWidgets('녹음하고 내 목소리·원어민과 번갈아 듣기', (tester) async {
      final recorder = FakeRecorder();
      final speaker = await scored(tester, recorder);
      final en = _container(tester).read(studyProvider).pack.sentences.first.en;

      await tester.tap(find.text('녹음해서 비교'));
      await tester.pump();
      expect(recorder.started, 1);
      expect(find.text('녹음 중 0초 / 8초'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('녹음 중 1초 / 8초'), findsOneWidget);

      await tester.tap(find.text('녹음 끝내기'));
      await tester.pump();
      expect(recorder.stopped, 1);
      expect(find.text('내 목소리 듣기'), findsOneWidget);

      await tester.tap(find.text('내 목소리 듣기'));
      await tester.pump();
      expect(recorder.plays, 1);

      speaker.spoken.clear();
      await _reveal(tester, find.text('원어민과 번갈아 듣기'));
      await tester.tap(find.text('원어민과 번갈아 듣기'));
      await tester.pump();
      expect(speaker.spoken, [(en, false)]);
      expect(recorder.plays, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(recorder.plays, 2);
    });

    testWidgets('8초가 지나면 녹음을 저절로 끝낸다', (tester) async {
      final recorder = FakeRecorder();
      await scored(tester, recorder);
      await tester.tap(find.text('녹음해서 비교'));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(recorder.stopped, 1);
      expect(find.text('원어민과 번갈아 듣기'), findsOneWidget);
    });

    testWidgets('마이크 권한이 없으면 안내한다', (tester) async {
      final recorder = FakeRecorder(allowed: false);
      await scored(tester, recorder);
      await tester.tap(find.text('녹음해서 비교'));
      await tester.pump();
      expect(find.text('녹음을 시작하지 못했어요. 마이크 권한을 확인해 주세요.'), findsOneWidget);
      expect(find.text('녹음해서 비교'), findsOneWidget);
    });
  });
}
