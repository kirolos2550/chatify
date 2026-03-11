import 'dart:async';

import 'package:flutter/foundation.dart';

class InAppMessageNotification {
  const InAppMessageNotification({
    required this.conversationId,
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.preview,
    required this.createdAt,
  });

  final String conversationId;
  final String messageId;
  final String senderId;
  final String senderName;
  final String preview;
  final DateTime createdAt;
}

class InAppNotificationCenter {
  InAppNotificationCenter();

  static final InAppNotificationCenter instance = InAppNotificationCenter();

  final StreamController<InAppMessageNotification> _controller =
      StreamController<InAppMessageNotification>.broadcast();

  Stream<InAppMessageNotification> get stream => _controller.stream;

  void publish(InAppMessageNotification notification) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(notification);
  }

  @visibleForTesting
  void debugReset() {
    // Kept for API symmetry in tests where notifications are isolated per run.
  }
}
