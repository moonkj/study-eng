import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/features/settings/settings_screen.dart';

class FakeReminder implements Reminder {
  FakeReminder({this.allowed = true});
  bool allowed;
  final scheduled = <(int, String)>[];
  int cancels = 0;
  DateTime? lastNotBefore;

  @override
  Future<bool> scheduleDaily(
    int minutes, {
    required String title,
    required String body,
    bool askPermission = true,
    DateTime? notBefore,
  }) async {
    if (!allowed) return false;
    scheduled.add((minutes, title));
    lastNotBefore = notBefore;
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
