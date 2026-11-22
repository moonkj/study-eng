import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 예약할 알림 한 건
class ReminderSlot {
  const ReminderSlot(this.at, this.title, this.body);
  final DateTime at;
  final String title;
  final String body;

  int get minutes => at.hour * 60 + at.minute;
}

/// 학습 알림. 매일 반복 대신 날짜별 일회성 알림을 여러 개 예약한다
/// (오늘 이미 공부했으면 오늘은 건너뛰고, 날마다 문구를 다르게 하려고). 앱을 열 때마다 다시 채운다.
abstract class Reminder {
  /// 기존 예약을 지우고 [slots] 를 예약한다. 권한이 없거나 지원하지 않으면 false.
  /// [askPermission] 이 false 면 권한을 묻지 않고, 이미 허용된 경우에만 예약한다 (앱을 열 때 갱신용).
  Future<bool> schedule(List<ReminderSlot> slots, {bool askPermission = true});
  Future<void> cancel();
}

/// 앞으로 [days]일 동안의 알림 계획.
/// - 오늘 이미 끝냈거나 시각이 지났으면 오늘은 건너뛴다.
/// - 그날까지 공부하지 않는다고 가정하고, 연속 기록·쉬는 날 상태에 맞는 문구를 고른다.
List<ReminderSlot> planReminders({
  required DateTime now,
  required DateTime studyToday,
  required int minutes,
  required bool doneToday,
  required int streak,
  required int restsLeft,
  required int longest,
  int days = 14,
}) {
  // 새벽 4시 전 알림(예: 01:00)은 그 학습일이 끝나 가는 밤이 아니라 '다음 달력 날짜'의 새벽에 울린다
  final nextCalendarDay = minutes < 4 * 60 ? 1 : 0;
  final slots = <ReminderSlot>[];
  for (var k = 0; k < days; k++) {
    if (k == 0 && doneToday) continue;
    final at = DateTime(
      studyToday.year,
      studyToday.month,
      studyToday.day + k + nextCalendarDay,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!at.isAfter(now)) continue;
    // 이 알림 전에 공부하지 않고 지나간 날 수
    final missed = doneToday ? k - 1 : k;
    final (String, String) text;
    if (missed == 0 && streak > 0) {
      text = ('오늘 하면 ${streak + 1}일', '표현 3개만 입에 붙여도 연속 기록이 이어져요.');
    } else if (missed > 0 && streak > 0 && missed <= restsLeft) {
      text = ('쉬는 날로 지켜 둔 $streak일', '오늘 하면 ${streak + 1}일로 이어져요. 15분이면 충분해요.');
    } else {
      text = reminderText(0, longest: longest > streak ? longest : streak);
    }
    slots.add(ReminderSlot(at, text.$1, text.$2));
  }
  return slots;
}

/// 다음 알림 시각: 오늘 그 시각이 이미 지났으면 내일
DateTime nextOccurrence(DateTime now, int minutes) {
  final today = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
  return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, minutes ~/ 60, minutes % 60);
}

/// 알림 문구: 연속 학습일에 따라 조금씩 다르게. 기록이 끊겼으면 탓하지 않고 복귀를 권한다.
(String, String) reminderText(int streakDays, {int longest = 0}) => switch (streakDays) {
  0 when longest >= 3 => ('다시 시작해 볼까요?', '최고 기록은 $longest일이었어요. 오늘 표현 3개로 다시 이어가요.'),
  0 => ('오늘의 영어', '15분이면 충분해요. 오늘의 표현 3개가 기다리고 있어요.'),
  < 7 => ('$streakDays일째 이어가는 중', '오늘도 15분, 표현 3개만 입에 붙여 봐요.'),
  _ => ('$streakDays일 연속 학습 중', '여기까지 온 루틴, 오늘도 이어가요.'),
};

class DeviceReminder implements Reminder {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 날짜별 알림 id (1..14). 2주 동안 앱을 열지 않아도 알림이 이어진다 (iOS 예약 한도 64개 안).
  static final _ids = [for (var i = 1; i <= 14; i++) i];

  bool get _supported => !kIsWeb;

  Future<void> _init() async {
    // 시간대는 예약할 때마다 다시 읽는다 (여행 중 시간대가 바뀌어도 그 지역 시각에 울리게)
    try {
      if (!_initialized) tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      if (!_initialized) tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    }
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> _hasPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<bool> schedule(List<ReminderSlot> slots, {bool askPermission = true}) async {
    if (!_supported) return false;
    try {
      await _init();
      if (!await (askPermission ? _requestPermission() : _hasPermission())) return false;
      // 예전 빌드가 다른 id 로 예약한 알림까지 모두 지운다
      await _plugin.cancelAll();
      for (var i = 0; i < slots.length && i < _ids.length; i++) {
        await _scheduleOne(_ids[i], slots[i]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _scheduleOne(int id, ReminderSlot slot) async {
    final at = slot.at;
    await _plugin.zonedSchedule(
      id: id,
      title: slot.title,
      body: slot.body,
      scheduledDate: tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'morning_routine',
          '아침 학습 알림',
          channelDescription: '매일 정한 시각에 오늘의 영어 루틴을 알려드려요.',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // 정확한 알람 권한 없이도 되는 방식 (몇 분 정도 늦을 수 있음)
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel() async {
    if (!_supported) return;
    try {
      await _init();
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

final reminderProvider = Provider<Reminder>((ref) => DeviceReminder());
