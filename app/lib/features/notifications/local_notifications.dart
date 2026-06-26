import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 시스템 트레이 알림 표시(flutter_local_notifications) 래퍼.
///
/// Flutter 는 foreground/data FCM 메시지를 자동으로 트레이에 띄우지 않으므로,
/// 도착한 메시지를 직접 `show()` 로 표시한다.
///
/// 같은 플러그인 인스턴스를 foreground(앱)와 background isolate 양쪽에서 쓰되,
/// 각 isolate 에서 `ensureInitialized()` 가 1회 init 을 보장한다.
class LocalNotifications {
  LocalNotifications._();

  /// FCM 기본 채널 id. AndroidManifest 의
  /// `default_notification_channel_id` 와 반드시 일치해야 한다.
  static const String channelId = 'high_importance_channel';
  static const String _channelName = '전중배 알림';
  static const String _channelDescription = '배차/매칭 등 중요 알림';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.high,
  );

  static bool _initialized = false;

  /// 플러그인 초기화 + Android 채널 생성(멱등). 앱 시작 시, 그리고
  /// 백그라운드 isolate 진입 시 각각 1회씩 호출한다.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    try {
      await _plugin.initialize(settings: initSettings);

      // Android 8.0+ 알림 채널 생성(이미 있으면 무시됨).
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (e) {
      _initialized = false; // 다음 호출에서 재시도 가능하도록.
      debugPrint('LocalNotifications.ensureInitialized failed: $e');
    }
  }

  /// FCM 메시지를 트레이에 표시. notification payload 가 없으면 data 로 폴백.
  static Future<void> showFromMessage(RemoteMessage message) async {
    await ensureInitialized();

    final notification = message.notification;
    final data = message.data;
    final title = notification?.title ?? data['title'] ?? '전중배';
    final body = notification?.body ?? data['body'] ?? '';

    // 빈 알림은 표시하지 않음(silent/data-only sync 메시지 보호).
    if (title.isEmpty && body.isEmpty) return;

    const androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    try {
      await _plugin.show(
        id: notification?.hashCode ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: details,
        payload: data.isEmpty ? null : data.toString(),
      );
    } catch (e) {
      debugPrint('LocalNotifications.show failed: $e');
    }
  }
}
