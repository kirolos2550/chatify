import 'dart:async';
import 'dart:convert';

import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:chatify/core/notifications/in_app_notification_center.dart';
import 'package:chatify/core/notifications/message_notification_decision_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class MessageNotificationOrchestrator {
  MessageNotificationOrchestrator._();

  static final MessageNotificationOrchestrator instance =
      MessageNotificationOrchestrator._();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final InAppNotificationCenter _notificationCenter =
      InAppNotificationCenter.instance;
  final MessageNotificationDecisionEngine _decisionEngine =
      MessageNotificationDecisionEngine();

  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _latestMessageSubscriptions =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, String> _userDisplayNameCache = <String, String>{};

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _conversationsSubscription;
  String? _activeUserId;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      return;
    }
    _started = true;

    _authSubscription = _auth.authStateChanges().listen(
      (user) {
        unawaited(_handleAuthChange(user));
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Message notification auth listener failed',
          error,
          stackTrace,
          event: 'notifications.orchestrator.auth_listener_failure',
          action: 'notifications.orchestrator.start',
        );
      },
    );
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;

    await _authSubscription?.cancel();
    _authSubscription = null;

    await _conversationsSubscription?.cancel();
    _conversationsSubscription = null;

    final subscriptions = _latestMessageSubscriptions.values.toList();
    _latestMessageSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }

    _activeUserId = null;
    _userDisplayNameCache.clear();
    _decisionEngine.reset();
  }

  Future<void> _handleAuthChange(User? user) async {
    await _conversationsSubscription?.cancel();
    _conversationsSubscription = null;

    final latestSubscriptions = _latestMessageSubscriptions.values.toList();
    _latestMessageSubscriptions.clear();
    for (final subscription in latestSubscriptions) {
      await subscription.cancel();
    }

    _activeUserId = user?.uid;
    _decisionEngine.reset();
    _userDisplayNameCache.clear();

    final uid = _activeUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }

    _conversationsSubscription = _firestore
        .collection(FirebasePaths.conversations)
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .listen(
          (snapshot) {
            unawaited(_syncConversationListeners(snapshot));
          },
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'Message notification conversation listener failed',
              error,
              stackTrace,
              event: 'notifications.orchestrator.conversation_listener_failure',
              action: 'notifications.orchestrator.watch_conversations',
              metadata: <String, Object?>{'userId': uid},
            );
          },
        );
  }

  Future<void> _syncConversationListeners(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final activeConversationIds = snapshot.docs.map((doc) => doc.id).toSet();

    _decisionEngine.clearInactiveConversations(activeConversationIds);

    final staleConversationIds = _latestMessageSubscriptions.keys
        .where(
          (conversationId) => !activeConversationIds.contains(conversationId),
        )
        .toList(growable: false);
    for (final conversationId in staleConversationIds) {
      final subscription = _latestMessageSubscriptions.remove(conversationId);
      await subscription?.cancel();
    }

    for (final conversationDoc in snapshot.docs) {
      final conversationId = conversationDoc.id;
      if (_latestMessageSubscriptions.containsKey(conversationId)) {
        continue;
      }
      _latestMessageSubscriptions[conversationId] = conversationDoc.reference
          .collection(FirebasePaths.messages)
          .orderBy('clientTimestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen(
            (messageSnapshot) {
              unawaited(
                _handleLatestMessageSnapshot(
                  conversationId: conversationId,
                  snapshot: messageSnapshot,
                ),
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              AppLogger.error(
                'Message notification message listener failed',
                error,
                stackTrace,
                event: 'notifications.orchestrator.message_listener_failure',
                action: 'notifications.orchestrator.watch_messages',
                metadata: <String, Object?>{'conversationId': conversationId},
              );
            },
          );
    }
  }

  Future<void> _handleLatestMessageSnapshot({
    required String conversationId,
    required QuerySnapshot<Map<String, dynamic>> snapshot,
  }) async {
    final currentUserId = _activeUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    if (snapshot.docs.isEmpty) {
      _decisionEngine.primeConversation(conversationId);
      return;
    }

    final latestDoc = snapshot.docs.first;
    final data = latestDoc.data();
    final messageId = latestDoc.id;
    final senderId = (data['senderId'] as String?)?.trim() ?? '';
    final deletedForAllAt = data['deletedForAllAt'];
    if (deletedForAllAt != null || _isDeletedForUser(data, currentUserId)) {
      _decisionEngine.primeConversation(
        conversationId,
        latestMessageId: messageId,
      );
      return;
    }

    final isConversationOpen = _isConversationOpen(conversationId);
    final shouldEmit = _decisionEngine.shouldEmitForLatestMessage(
      conversationId: conversationId,
      messageId: messageId,
      senderId: senderId,
      currentUserId: currentUserId,
      isConversationOpen: isConversationOpen,
    );
    if (!shouldEmit) {
      return;
    }

    final senderName = await _resolveSenderName(senderId);
    final preview = await _buildPreview(data);
    _notificationCenter.publish(
      InAppMessageNotification(
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        senderName: senderName,
        preview: preview,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  bool _isConversationOpen(String conversationId) {
    final segments = AppRouter.router.state.uri.pathSegments;
    if (segments.length < 2 || segments.first != 'chat') {
      return false;
    }
    final routeConversationId = Uri.decodeComponent(segments[1]);
    return routeConversationId == conversationId;
  }

  bool _isDeletedForUser(Map<String, dynamic> data, String userId) {
    final raw = data['deletedForUserIds'];
    if (raw is! List) {
      return false;
    }
    return raw.whereType<String>().contains(userId);
  }

  Future<String> _resolveSenderName(String senderId) async {
    if (senderId.isEmpty) {
      return 'Unknown sender';
    }
    final cached = _userDisplayNameCache[senderId];
    if (cached != null) {
      return cached;
    }

    try {
      final snapshot = await _firestore
          .collection(FirebasePaths.users)
          .doc(senderId)
          .get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final displayName = (data['displayName'] as String?)?.trim();
      final phone = (data['phone'] as String?)?.trim();
      final resolved = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : (phone != null && phone.isNotEmpty)
          ? phone
          : senderId;
      _userDisplayNameCache[senderId] = resolved;
      return resolved;
    } catch (_) {
      _userDisplayNameCache[senderId] = senderId;
      return senderId;
    }
  }

  Future<String> _buildPreview(Map<String, dynamic> data) async {
    final type = (data['type'] as String?)?.trim().toLowerCase() ?? 'text';
    if (type != 'text') {
      return _mediaPreviewFallback(type);
    }

    final ciphertext = (data['ciphertext'] as String?)?.trim() ?? '';
    if (ciphertext.isEmpty) {
      return 'New message';
    }

    final decrypted = _decryptPreview(ciphertext);
    final compact = decrypted.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) {
      return 'New message';
    }
    if (compact.length <= 120) {
      return compact;
    }
    return '${compact.substring(0, 120)}...';
  }

  String _decryptPreview(String ciphertext) {
    try {
      return utf8.decode(base64Decode(ciphertext));
    } catch (_) {
      return ciphertext;
    }
  }

  String _mediaPreviewFallback(String type) {
    switch (type) {
      case 'voice':
        return 'Voice note';
      case 'image':
        return 'Image';
      case 'video':
        return 'Video';
      case 'file':
        return 'File';
      case 'videonote':
      case 'video_note':
        return 'Video note';
      case 'system':
        return 'System message';
      default:
        return 'New message';
    }
  }
}
