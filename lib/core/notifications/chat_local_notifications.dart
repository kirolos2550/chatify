import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ChatLocalNotifications {
  ChatLocalNotifications(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  Future<void> Function(String payload)? _onNotificationTap;

  Future<void> initialize({
    Future<void> Function(String payload)? onNotificationTap,
  }) async {
    if (onNotificationTap != null) {
      _onNotificationTap = onNotificationTap;
    }
    if (_initialized) {
      return;
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.trim().isEmpty) {
          return;
        }
        final handler = _onNotificationTap;
        if (handler == null) {
          return;
        }
        unawaited(handler(payload.trim()));
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload?.trim();
    if (launchPayload != null && launchPayload.isNotEmpty) {
      final handler = _onNotificationTap;
      if (handler != null) {
        unawaited(handler(launchPayload));
      }
    }
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  Future<void> showMessageAlert({
    required int id,
    required String sender,
    required String conversationId,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Encrypted chat alerts',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id,
      sender,
      'New encrypted message',
      details,
      payload: conversationId,
    );
  }

  Future<void> showIncomingCallAlert({
    required int id,
    required String callerLabel,
    required String callId,
    required String callType,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'incoming_calls',
        'Incoming Calls',
        channelDescription: 'Incoming voice/video calls',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
      ),
      iOS: DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    await _plugin.show(
      id,
      'Incoming $callType call',
      'from $callerLabel',
      details,
      payload: 'call:$callId',
    );
  }
}
