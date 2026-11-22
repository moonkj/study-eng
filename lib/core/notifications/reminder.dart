import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 매일 같은 시각의 학습 알림
abstract class Reminder {
  /// 매일 [minutes](자정부터 분) 에 알림을 예약한다. 권한이 없거나 지원하지 않으면 false.
  /// [askPermission] 이 false 면 권한을 묻지 않고, 이미 허용된 경우에만 예약한다 (앱을 열 때 갱신용).
  Future<bool> scheduleDaily(int minutes, {required String title, required String body, bool askPermission = true});
  Future<void> cancel();
}

/// 다음 알림 시각: 오늘 그 시각이 이미 지났으면 내일
DateTime nextOccurrence(DateTime now, int minutes) {
  final today = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
  return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, minutes ~/ 60, minutes % 60);
}

/// 알림 문구: 연속 학습일에 따라 조금씩 다르게
(String, String) reminderText(int streakDays) => switch (streakDays) {
  0 => ('오늘의 영어', '10분이면 충분해요. 오늘의 표현 3개가 기다리고 있어요.'),
  < 7 => ('$streakDays일째 이어가는 중', '오늘도 10분, 표현 3개만 입에 붙여 봐요.'),
  _ => ('$streakDays일 연속 학습 중', '여기까지 온 루틴, 오늘도 이어가요.'),
};

class DeviceReminder implements Reminder {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _id = 1;

  bool get _supported => !kIsWeb;

  Future<void> _init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    }
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
  Future<bool> scheduleDaily(
    int minutes, {
    required String title,
    required String body,
    bool askPermission = true,
  }) async {
    if (!_supported) return false;
    try {
      await _init();
      if (!await (askPermission ? _requestPermission() : _hasPermission())) return false;
      final next = nextOccurrence(DateTime.now(), minutes);
      await _plugin.zonedSchedule(
        id: _id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime(tz.local, next.year, next.month, next.day, next.hour, next.minute),
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
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_supported) return;
    try {
      await _init();
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}

final reminderProvider = Provider<Reminder>((ref) => DeviceReminder());
