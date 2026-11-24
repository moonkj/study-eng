import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/app.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/audio/tts.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/correct_source.dart';
import 'package:todaye/data/pack_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/data/topic_map.dart';
import 'package:todaye/domain/study_log.dart';
import 'package:todaye/features/my_sentence/my_sentence_screen.dart';

import '../domain/pack_source_test.dart' show FakeSource, serverFixture;
import '../domain/reminder_test.dart' show FakeReminder;
import 'daily_flow_test.dart' show seeded, setPhone, FakeSpeaker;

class _FakeCorrect implements CorrectSource {
  final sent = <String>[];

  @override
  Future<Correction> correct({
    required ({String pattern, String highlight, String meaning}) expression,
    String? situationKo,
    required String sentence,
    required String level,
  }) async {
    sent.add(sentence);
    return const Correction(
      ok: false,
      corrected: "I've been meaning to call my mom.",
      notes: "'been meaning to' 다음에는 동사원형을 써요.",
      errorType: 'grammar_form',
      usedExpression: true,
    );
  }
}

Widget _app(String initial, {CorrectSource? correct, SavedData? data}) => ProviderScope(
  overrides: [
    reminderProvider.overrideWithValue(FakeReminder()),
    speakerProvider.overrideWithValue(FakeSpeaker()),
    storeProvider.overrideWithValue(MemoryStore(data ?? seeded())),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8)),
    correctSourceProvider.overrideWithValue(correct),
  ],
  child: TodayeApp(initialLocation: initial),
);

void main() {
  test('서버 요청에 최근 주제·자주 틀리는 유형·주간 시리즈 다음 회를 담고, 받은 대화로 시리즈를 이어 간다', () async {
    final d = seeded();
    final source = FakeSource();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(
          MemoryStore(
            SavedData(
              profile: d.profile,
              contentStep: d.contentStep,
              onboarded: true,
              log: {
                ...d.log,
                '2026-11-20': const DayRecord(accuracy: 0.8, levelScore: 740, topic: '출근길', errors: {'preposition': 2}),
                '2026-11-21': const DayRecord(
                  accuracy: 0.8,
                  levelScore: 742,
                  topic: '점심 약속',
                  errors: {'preposition': 1, 'word_order': 1},
                ),
              },
              series: const SeriesState(
                title: 'Coffee Break',
                episode: 2,
                cast: ['Mina', 'Jake'],
                summary: '지난 회',
                date: '2026-11-21',
              ),
            ),
          ),
        ),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8)),
        packSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(c.dispose);
    c.read(studyProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final req = source.requests.single;
    expect(req['recentTopics'], ['점심 약속', '출근길']);
    expect(req['weakErrorTypes'], ['preposition']); // 2번 이상 틀린 유형만
    expect(req['topicHint'], isA<String>());
    expect(['점심 약속', '출근길'], isNot(contains(req['topicHint'])));
    expect(req['series'], {
      'title': 'Coffee Break',
      'episode': 3,
      'cast': ['Mina', 'Jake'],
      'lastSummary': '지난 회',
    });
    final s = c.read(studyProvider);
    expect(s.pack.dialogue!.episode, 3);
    expect(s.series!.episode, 3);
    expect(s.series!.date, '2026-11-22');
  });

  test('7회를 마친 시리즈는 이어 보내지 않고, 오답 유형은 루틴을 끝낼 때 기록한다', () {
    const done = SeriesState(title: 'A', episode: 7, cast: ['x'], date: '2026-11-21');
    expect(done.continuesOn(DateTime(2026, 11, 22)), isFalse);
    expect(done.continuesOn(DateTime(2026, 11, 21)), isTrue); // 같은 날 다시 만들 때는 같은 회차
    final json = serverFixture();
    final pack = packFromJson(json, learned: const {}, today: DateTime(2026, 11, 22));
    expect(pack.quiz.map((q) => q.errorType), ['word_order', 'word_choice']);
    expect(pack.dialogue!.cast, ['Mina', 'Jake']);
    expect(pack.sentences.any((s) => s.focus == 'Could I get'), isTrue); // 표현 문장
  });

  test('주제 힌트: 같은 날짜면 같은 상황, 최근 주제는 건너뛰고, 일주일이면 7개 축을 모두 돈다', () {
    final d = DateTime(2026, 11, 22);
    expect(topicHintFor(d, const []).id, topicHintFor(d, const []).id);
    final first = topicHintFor(d, const []);
    expect(topicHintFor(d, [first.nameKo]).id, isNot(first.id));
    final axes = {for (var i = 0; i < 7; i++) topicHintFor(DateTime(2026, 11, 22 + i), const []).axisId};
    expect(axes.length, 7);
  });

  test('첨삭 주소는 학습 팩 주소에서 만든다', () {
    expect(correctUrlFor('https://x.net/dailyPack', ''), 'https://x.net/correct');
    expect(correctUrlFor('http://localhost:8787/dailyPack', ''), 'http://localhost:8787/correct');
    expect(correctUrlFor('', ''), isNull);
    expect(correctUrlFor('https://x.net/dailyPack', 'https://y/c'), 'https://y/c');
    expect(usesExpression("I've been meaning to call her.", 'been meaning to'), isTrue);
    expect(usesExpression('Can you make it on Friday?', 'make it ~'), isTrue);
    expect(usesExpression('I want to call her.', 'been meaning to'), isFalse);
  });

  testWidgets('내 상황으로 말하기: 첨삭 결과를 보여 준다', (tester) async {
    await setPhone(tester);
    final correct = _FakeCorrect();
    await tester.pumpWidget(_app('/my-sentence', correct: correct));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, "I've been meaning to calling my mom.");
    await tester.pump();
    await tester.tap(find.text('첨삭 받기'));
    await tester.pumpAndSettle();
    expect(correct.sent.single, "I've been meaning to calling my mom.");
    expect(find.text('이렇게 고치면 더 자연스러워요'), findsOneWidget);
    expect(find.text("I've been meaning to call my mom."), findsOneWidget);
  });

  testWidgets('서버가 없으면 표현을 넣었는지 확인하고 예문과 비교하게 한다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app('/my-sentence'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'I want to call my mom.');
    await tester.pump();
    await tester.tap(find.text('확인하기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('가 문장에 없어요'), findsOneWidget);
    expect(find.text('예문과 비교해 보세요'), findsOneWidget);
  });
}
