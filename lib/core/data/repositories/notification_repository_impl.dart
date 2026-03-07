import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/repositories/notification_repository.dart';
import 'package:chatify/core/notifications/chat_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: NotificationRepository)
class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl(this._messaging, this._localNotifications);

  final FirebaseMessaging _messaging;
  final ChatLocalNotifications _localNotifications;

  @override
  Future<Result<String>> registerDeviceToken() async {
    try {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token == null) {
        return const FailureResult(Failure('Could not get FCM token'));
      }
      return Success(token);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> showChatNotification({
    required String conversationId,
    required String sender,
  }) async {
    try {
      await _localNotifications.initialize();
      await _localNotifications.showMessageAlert(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        sender: sender,
        conversationId: conversationId,
      );
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }
}
