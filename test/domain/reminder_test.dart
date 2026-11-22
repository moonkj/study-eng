import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/features/settings/settings_screen.dart';

class FakeReminder implements Reminder {
  FakeReminder({this.allowed = true});
  bool allowed;

  /// 예약할 때마다 첫 알림의 (시각, 제목)
  final scheduled = <(int, String)>[];
  List<ReminderSlot> lastSlots = const [];
  int cancels = 0;

  @override
  Future<bool> schedule(List<ReminderSlot> slots, {bool askPermission = true}) async {
    if (!allowed) return false;
    scheduled.add((slots.first.minutes, slots.first.title));
    lastSlots = slots;
    return true;
  }

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  test('다음 알림 시각: 지났으면 내일, 아니면 오늘', () {
    expect(nextOccurrence(DateTime(2026, 11, 22, 6, 0), 450), DateTime(2026, 11, 22, 7, 30));
    expect(nextOccurrence(DateTime(2026, 11, 22, 7, 30), 450), DateTime(2026, 11, 23, 7, 30));
    expect(nextOccurrence(DateTime(2026, 12, 31, 23, 0), 450), DateTime(2027, 1, 1, 7, 30));
  });

  test('알림 문구는 연속 학습일에 따라 달라진다', () {
    expect(reminderText(0).$1, '오늘의 영어');
    expect(reminderText(3).$1, '3일째 이어가는 중');
    expect(reminderText(12).$1, '12일 연속 학습 중');
    expect(reminderText(0, longest: 9).$1, '다시 시작해 볼까요?'); // 끊겼으면 탓하지 않고 복귀 권유
  });

  test('알림 계획: 오늘 끝냈으면 오늘은 건너뛰고, 날마다 상태에 맞는 문구', () {
    final plan = planReminders(
      now: DateTime(2026, 11, 22, 9),
      studyToday: DateTime(2026, 11, 22),
      minutes: 20 * 60,
      doneToday: true,
      streak: 8,
      restsLeft: 1,
      longest: 8,
    );
    expect(plan.length, 13); // 14일 중 오늘(끝냄) 제외
    expect(plan.first.at, DateTime(2026, 11, 23, 20));
    expect(plan[0].title, '오늘 하면 9일');
    expect(plan[1].title, '쉬는 날로 지켜 둔 8일'); // 하루 빠짐 → 쉬는 날 1개로 지킴
    expect(plan[2].title, '다시 시작해 볼까요?'); // 쉬는 날을 넘겨 끊김
    final notDone = planReminders(
      now: DateTime(2026, 11, 22, 9),
      studyToday: DateTime(2026, 11, 22),
      minutes: 20 * 60,
      doneToday: false,
      streak: 8,
      restsLeft: 0,
      longest: 8,
    );
    expect(notDone.first.at, DateTime(2026, 11, 22, 20)); // 오늘 저녁
    expect(notDone.length, 14);
  });

  test('새벽 4시 전 알림은 학습일의 다음 달력 날짜 새벽에 울린다', () {
    final plan = planReminders(
      now: DateTime(2026, 11, 22, 10),
      studyToday: DateTime(2026, 11, 22),
      minutes: 60,
      doneToday: true,
      streak: 3,
      restsLeft: 0,
      longest: 3,
    );
    // 22일 학습일을 끝냈으니 첫 알림은 23일 학습일 몫인 24일 01:00
    expect(plan.first.at, DateTime(2026, 11, 24, 1));
    expect(plan.first.title, '오늘 하면 4일');
  });

  test('시각 표시', () {
    expect(formatMinutes(450), '오전 7:30');
    expect(formatMinutes(0), '오전 12:00');
    expect(formatMinutes(13 * 60 + 5), '오후 1:05');
  });

  test('알림을 켜면 예약하고 저장, 권한이 없으면 저장하지 않는다, 끄면 취소', () async {
    final reminder = FakeReminder(allowed: false);
    final store = MemoryStore();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 9)),
        reminderProvider.overrideWithValue(reminder),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    expect(await ctl.setReminder(450), isFalse);
    expect(c.read(studyProvider).settings.reminderMinutes, isNull);

    reminder.allowed = true;
    expect(await ctl.setReminder(450), isTrue);
    expect(store.load()!.settings.reminderMinutes, 450);
    expect(reminder.scheduled.single, (450, '오늘의 영어'));

    await ctl.setReminder(null);
    expect(reminder.cancels, 1);
    expect(store.load()!.settings.reminderMinutes, isNull);
    c.dispose();
  });
}
