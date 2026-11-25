import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/core/theme/app_theme.dart';
import 'package:todaye/core/theme/tokens.dart';
import 'package:todaye/core/widgets/widgets.dart';

Widget _wrap(Widget child, {bool reduceMotion = false, AppPalette palette = AppPalette.light}) => MaterialApp(
  theme: buildAppTheme(palette),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Padding(padding: const EdgeInsets.all(AppSpace.gutter), child: child),
      ),
    ),
  ),
);

/// 링(CircularProgressIndicator)의 현재 색·굵기
CircularProgressIndicator _ring(WidgetTester tester) =>
    tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));

void main() {
  group('LevelScale', () {
    test('요약 문장: 범위·목표·남은 단계·지난번', () {
      expect(
        LevelScale.describe(current: 'IM2', currentHigh: 'IM3', target: 'IH', previous: 'IM1'),
        '등급 눈금. 지금 예상 IM2에서 IM3, 목표 IH, 목표까지 1단계, 지난번 IM1',
      );
      expect(LevelScale.describe(current: 'IM3', target: 'IM3'), '등급 눈금. 지금 예상 IM3, 목표 IM3, 목표 달성');
      expect(LevelScale.describe(target: 'IM2'), '등급 눈금. 아직 예상 등급 없음, 목표 IM2');
    });

    testWidgets('스크린리더에는 한 문장 요약만 읽히고, 목표는 글자로도 보인다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const LevelScale(current: 'IM2', currentHigh: 'IM3', target: 'IH')));
      expect(find.bySemanticsLabel('등급 눈금. 지금 예상 IM2에서 IM3, 목표 IH, 목표까지 1단계'), findsOneWidget);
      // 눈금 글자 9개 + '목표' 표시 (색만으로 목표를 알리지 않는다)
      for (final l in ['NL', 'NM', 'NH', 'IL', 'IM1', 'IM2', 'IM3', 'IH', 'AL']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(find.text('목표'), findsOneWidget);
      // 개별 눈금 글자는 따로 읽히지 않는다
      expect(find.bySemanticsLabel('NL'), findsNothing);
      handle.dispose();
    });

    testWidgets('글씨 2배·좁은 폭에서도 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_wrap(const LevelScale(current: 'IL', target: 'AL', previous: 'NH')));
      expect(tester.takeException(), isNull);
    });
  });

  group('TimerRing', () {
    testWidgets('남은 초를 보이고, 5초 이하면 숫자를 caution 색으로', (tester) async {
      await tester.pumpWidget(_wrap(const TimerRing(phase: TimerPhase.prep, remaining: 12, total: 30)));
      expect(find.text('12'), findsOneWidget);
      expect(tester.widget<Text>(find.text('12')).style!.color, isNot(AppPalette.light.caution));
      expect(_ring(tester).value, closeTo(12 / 30, 1e-9));

      await tester.pumpWidget(_wrap(const TimerRing(phase: TimerPhase.prep, remaining: 5, total: 30)));
      expect(tester.widget<Text>(find.text('5')).style!.color, AppPalette.light.caution);
    });

    testWidgets('준비→답하기: 240ms 동안 색·굵기를 보간한다', (tester) async {
      await tester.pumpWidget(_wrap(const TimerRing(phase: TimerPhase.prep, remaining: 30, total: 30)));
      expect(_ring(tester).color, AppPalette.light.timerPrep);
      final thin = _ring(tester).strokeWidth;
      expect(thin, 5);

      await tester.pumpWidget(_wrap(const TimerRing(phase: TimerPhase.speak, remaining: 45, total: 45)));
      await tester.pump(const Duration(milliseconds: 120));
      final mid = _ring(tester);
      expect(mid.color, isNot(AppPalette.light.timerPrep));
      expect(mid.color, isNot(AppPalette.light.timerSpeak));
      expect(mid.strokeWidth, inExclusiveRange(5, 7));

      await tester.pump(AppMotion.phase);
      expect(_ring(tester).color, AppPalette.light.timerSpeak);
      expect(_ring(tester).strokeWidth, closeTo(7, 1e-9));
    });

    testWidgets('동작 줄이기면 바로 바뀐다', (tester) async {
      await tester.pumpWidget(
        _wrap(const TimerRing(phase: TimerPhase.prep, remaining: 3, total: 30), reduceMotion: true),
      );
      await tester.pumpWidget(
        _wrap(const TimerRing(phase: TimerPhase.speak, remaining: 45, total: 45), reduceMotion: true),
      );
      await tester.pump();
      expect(_ring(tester).color, AppPalette.light.timerSpeak);
    });

    testWidgets('단계 이름만 live region 으로 읽고, 숫자는 읽지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(const TimerRing(phase: TimerPhase.speak, remaining: 20, total: 45, semanticsLabel: 'Q5 답하기')),
      );
      expect(find.bySemanticsLabel('Q5 답하기'), findsOneWidget);
      expect(find.bySemanticsLabel('20'), findsNothing);
      final node = tester.getSemantics(find.bySemanticsLabel('Q5 답하기'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('emphasizeCaution: 남은 5초부터 링이 굵어지고(8) 숫자가 커진다', (tester) async {
      await tester.pumpWidget(
        _wrap(const TimerRing(phase: TimerPhase.prep, remaining: 6, total: 30, emphasizeCaution: true)),
      );
      expect(_ring(tester).strokeWidth, 5);
      final normal = tester.widget<Text>(find.text('6')).style!.fontSize!;
      await tester.pumpWidget(
        _wrap(const TimerRing(phase: TimerPhase.prep, remaining: 5, total: 30, emphasizeCaution: true)),
      );
      await tester.pump(AppMotion.phase);
      expect(_ring(tester).strokeWidth, closeTo(8, 1e-9));
      final big = tester.widget<Text>(find.text('5')).style!;
      expect(big.fontSize, greaterThan(normal));
      expect(big.fontWeight, FontWeight.w700);
      expect(big.color, AppPalette.light.caution);
    });

    testWidgets('미니(32)·글씨 2배에서도 숫자가 링 밖으로 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _wrap(
          const Align(
            alignment: Alignment.topLeft,
            child: TimerRing(phase: TimerPhase.prep, remaining: 45, total: 45, size: TimerRing.mini),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(TimerRing)), const Size(32, 32));
    });
  });

  group('EmptyState', () {
    testWidgets('다음 행동 + 걸리는 시간 + 버튼', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          EmptyState(
            icon: Icons.timer_outlined,
            message: '첫 모의고사로 지금 위치를 확인해요',
            time: '약 20분',
            actionLabel: '모의고사 보기',
            onAction: () => tapped++,
          ),
        ),
      );
      expect(find.text('첫 모의고사로 지금 위치를 확인해요 · 약 20분'), findsOneWidget);
      await tester.tap(find.text('모의고사 보기'));
      expect(tapped, 1);
    });

    testWidgets('행동이 없으면 버튼을 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(icon: Icons.mic_none_rounded, message: '오늘 토스 말하기를 하면 유형별 점수가 쌓여요', actionLabel: '시작')),
      );
      expect(find.text('시작'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('ActionRow', () {
    testWidgets('완료는 글자 "완료"로, 잠김은 "잠김"으로 보이고 잠기면 눌리지 않는다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              ActionRow(number: 1, title: '표현 3개', subtitle: '3분', state: ActionRowState.done, onTap: () => taps++),
              ActionRow(icon: Icons.timer_outlined, title: '모의고사', state: ActionRowState.locked, onTap: () => taps++),
              ActionRow(number: 2, title: '단어 10개', state: ActionRowState.emphasis, progress: 0.5, value: '이어서'),
            ],
          ),
        ),
      );
      expect(find.text('완료'), findsOneWidget);
      expect(find.text('3분'), findsNothing); // 완료면 부제 숨김
      expect(find.text('잠김'), findsOneWidget);
      await tester.tap(find.text('모의고사'));
      expect(taps, 0);
      await tester.tap(find.text('표현 3개'));
      expect(taps, 1);
      expect(find.byType(ThinProgress), findsOneWidget);
      expect(tester.getSize(find.byType(ActionRow).at(2)).height, greaterThanOrEqualTo(ActionRow.emphasisMinHeight));
    });

    testWidgets('글씨 2배에서 긴 값이 있어도 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _wrap(ActionRow(icon: Icons.auto_awesome_outlined, title: '학습 내용', value: '기본 샘플 (서버 미연결)', onTap: () {})),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ScoreBadge: 범위 표기와 목표 이상(아이콘 + 문장)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const ScoreBadge(level: 'IM2', upTo: 'IM3', met: true)));
    expect(find.text('IM2~IM3'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('등급 IM2에서 IM3, 목표 이상'), findsOneWidget);

    await tester.pumpWidget(_wrap(const ScoreBadge(level: 'IL', met: false)));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.bySemanticsLabel('등급 IL, 목표 미만'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('StatTile: 오를 때만 변화량을 보인다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Row(
          children: [
            Expanded(
              child: StatTile(value: '12', label: '외운 단어', delta: 3),
            ),
            Expanded(
              child: StatTile(value: '80%', label: '정답률', delta: -5),
            ),
          ],
        ),
      ),
    );
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('-5'), findsNothing);
  });

  testWidgets('AppBanner: 종류를 아이콘과 앞말로 알리고 버튼은 최대 2개', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        AppBanner(
          kind: BannerKind.success,
          title: '목표 달성!',
          message: '다음 목표로 올릴까요?',
          actions: [
            TextButton(onPressed: () {}, child: const Text('괜찮아요')),
            Expanded(
              child: FilledButton(onPressed: () {}, child: const Text('올리기')),
            ),
          ],
        ),
      ),
    );
    expect(find.text('목표 달성!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^완료')), findsWidgets);
    expect(() => AppBanner(message: 'x', actions: [Container(), Container(), Container()]), throwsAssertionError);
    handle.dispose();
  });

  testWidgets('SectionHeader: 제목은 머리글로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const SectionHeader(title: '오늘의 루틴', trailing: '1/4 · 남은 11분')));
    expect(find.text('1/4 · 남은 11분'), findsOneWidget);
    expect(tester.getSemantics(find.text('오늘의 루틴')).flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  test('의미 색: 밝은·어두운 팔레트 모두 타이머·목표선 색을 가진다', () {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      expect(p.timerPrep, p.penBlue);
      expect(p.timerSpeak, p.ember);
      expect(p.target.a, closeTo(0.5, 0.01));
    }
  });

  testWidgets('ActionRow current: 펜 파랑 테두리, 부제와 진행 막대가 함께, 오른쪽 값', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ActionRow(
          number: 2,
          title: '단어',
          subtitle: '10개 · 3분',
          value: '지금',
          state: ActionRowState.current,
          progress: 0.4,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('10개 · 3분'), findsOneWidget);
    expect(find.byType(ThinProgress), findsOneWidget);
    expect(tester.widget<Text>(find.text('지금')).style!.color, AppPalette.light.penBlue);
    final shape = tester.widget<Material>(find.byType(Material).last).shape as RoundedRectangleBorder;
    expect(shape.side.color, AppPalette.light.penBlue);
  });
}
