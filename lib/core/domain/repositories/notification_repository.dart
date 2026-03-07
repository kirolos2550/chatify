import 'package:chatify/core/common/result.dart';

abstract interface class NotificationRepository {
  Future<Result<String>> registerDeviceToken();

  Future<Result<void>> showChatNotification({
    required String conversationId,
    required String sender,
  });
}
