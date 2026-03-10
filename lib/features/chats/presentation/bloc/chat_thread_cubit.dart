import 'dart:async';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/crypto/crypto_engine.dart';
import 'package:chatify/core/domain/entities/message.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/message_repository.dart';
import 'package:chatify/features/chats/domain/usecases/send_text_message_use_case.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ChatMessageAck { sent, delivered, read }

class ChatMessageView {
  const ChatMessageView({
    required this.id,
    required this.senderId,
    required this.type,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.ack = ChatMessageAck.sent,
    this.replyToMessageId,
    this.editedAt,
    this.deletedForAllAt,
    this.isStarred = false,
    this.isPinned = false,
    this.reactionsByUser = const <String, String>{},
  });

  final String id;
  final String senderId;
  final MessageType type;
  final String text;
  final DateTime sentAt;
  final bool isMine;
  final ChatMessageAck ack;
  final String? replyToMessageId;
  final DateTime? editedAt;
  final DateTime? deletedForAllAt;
  final bool isStarred;
  final bool isPinned;
  final Map<String, String> reactionsByUser;

  bool get isDeleted => deletedForAllAt != null;
}

class ChatThreadState {
  const ChatThreadState({
    this.messages = const [],
    this.loading = true,
    this.sending = false,
    this.replyingTo,
    this.errorMessage,
  });

  final List<ChatMessageView> messages;
  final bool loading;
  final bool sending;
  final ChatMessageView? replyingTo;
  final String? errorMessage;

  ChatThreadState copyWith({
    List<ChatMessageView>? messages,
    bool? loading,
    bool? sending,
    ChatMessageView? replyingTo,
    String? errorMessage,
    bool clearError = false,
    bool clearReplying = false,
  }) {
    return ChatThreadState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      replyingTo: clearReplying ? null : replyingTo ?? this.replyingTo,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ChatThreadCubit extends Cubit<ChatThreadState> {
  ChatThreadCubit(
    this._messageRepository,
    this._sendTextMessage,
    this._cryptoEngine,
    this._currentUserId,
  ) : super(const ChatThreadState());

  final MessageRepository _messageRepository;
  final SendTextMessageUseCase _sendTextMessage;
  final CryptoEngine _cryptoEngine;
  final String _currentUserId;

  StreamSubscription<List<Message>>? _messagesSubscription;
  String? _conversationId;
  bool _markReadInFlight = false;
  bool _markReadQueued = false;
  bool _processingSnapshots = false;
  List<Message>? _queuedSnapshot;
  DateTime? _lastSnapshotPerfLogAt;
  DateTime? _lastDecryptFallbackLogAt;
  int _suppressedDecryptFallbackCount = 0;
  DateTime? _lastMarkReadAt;
  String? _lastUnreadIncomingIdMarked;
  final Map<String, String> _decryptCacheByCiphertext = <String, String>{};
  final List<DateTime> _recentSendAttempts = <DateTime>[];
  static const int _snapshotChunkSize = 40;
  static const Duration _decryptFallbackLogWindow = Duration(seconds: 20);
  static const Duration _snapshotPerfLogInterval = Duration(seconds: 15);

  void start(String conversationId) {
    final startedAt = DateTime.now().toUtc();
    _logActionStart('chat.start', <String, Object?>{
      'conversationId': conversationId,
    });
    _conversationId = conversationId;
    _queuedSnapshot = null;
    _processingSnapshots = false;
    _decryptCacheByCiphertext.clear();
    _recentSendAttempts.clear();
    _lastSnapshotPerfLogAt = null;
    _lastDecryptFallbackLogAt = null;
    _suppressedDecryptFallbackCount = 0;
    _lastUnreadIncomingIdMarked = null;
    emit(state.copyWith(loading: true, clearError: true));
    _messagesSubscription?.cancel();
    try {
      _messagesSubscription = _messageRepository
          .watchMessages(conversationId)
          .listen(
            (messages) {
              _enqueueSnapshot(
                conversationId: conversationId,
                messages: messages,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              AppLogger.error(
                'Chat message stream failed',
                error,
                stackTrace,
                event: 'chat.stream.failure',
                action: 'chat.start',
                source: 'ChatThreadCubit',
                operation: 'watchMessages',
                metadata: <String, Object?>{'conversationId': conversationId},
              );
              emit(
                state.copyWith(loading: false, errorMessage: error.toString()),
              );
            },
          );
      final listenReadyMs = DateTime.now()
          .toUtc()
          .difference(startedAt)
          .inMilliseconds;
      AppLogger.info(
        'Chat stream subscribed',
        event: 'chat.stream.subscribed',
        action: 'chat.start',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'subscribeMs': listenReadyMs,
        },
      );
    } catch (error) {
      AppLogger.error(
        'Chat stream setup failed',
        error,
        StackTrace.current,
        event: 'chat.stream.setup_failure',
        action: 'chat.start',
        source: 'ChatThreadCubit',
        operation: 'start',
        metadata: <String, Object?>{'conversationId': conversationId},
      );
      emit(state.copyWith(loading: false, errorMessage: error.toString()));
    }
  }

  Future<bool> sendText(String rawText) async {
    return _sendTypedMessage(content: rawText.trim(), type: MessageType.text);
  }

  Future<bool> sendTypedMessage({
    required String content,
    required MessageType type,
  }) async {
    return _sendTypedMessage(content: content.trim(), type: type);
  }

  Future<bool> _sendTypedMessage({
    required String content,
    required MessageType type,
  }) async {
    final conversationId = _conversationId;
    if (conversationId == null || content.isEmpty) {
      AppLogger.warning(
        'Chat send skipped due to missing conversation or empty content',
        event: 'chat.send.validation_failed',
        action: 'chat.send',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'contentLength': content.length,
          'type': type.name,
        },
      );
      return false;
    }
    _logActionStart('chat.send', <String, Object?>{
      'conversationId': conversationId,
      'messageType': type.name,
      'messageBody': content,
    });
    if (!_allowSendNow()) {
      _logActionFailure(
        action: 'chat.send',
        reason: 'rate_limited',
        metadata: <String, Object?>{'conversationId': conversationId},
      );
      emit(
        state.copyWith(
          errorMessage:
              'Too many messages sent in a short time. Please wait a bit.',
        ),
      );
      return false;
    }

    emit(state.copyWith(sending: true, clearError: true));
    final result = await _sendTextMessage(
      SendTextMessageParams(
        conversationId: conversationId,
        senderId: _currentUserId,
        plaintext: content,
        peerDeviceId: _peerDeviceId(conversationId),
        messageType: type,
        replyToMessageId: state.replyingTo?.id,
      ),
    );

    if (result is FailureResult<void>) {
      _logFailureResult(
        result,
        event: 'chat.send.failure',
        action: 'chat.send',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageType': type.name,
          'messageBody': content,
        },
      );
      emit(
        state.copyWith(sending: false, errorMessage: result.failure.message),
      );
      return false;
    }

    _logActionSuccess('chat.send', <String, Object?>{
      'conversationId': conversationId,
      'messageType': type.name,
    });
    emit(state.copyWith(sending: false, clearError: true, clearReplying: true));
    return true;
  }

  void startReply(ChatMessageView message) {
    emit(state.copyWith(replyingTo: message, clearError: true));
  }

  void cancelReply() {
    emit(state.copyWith(clearReplying: true, clearError: true));
  }

  Future<bool> editMessage({
    required ChatMessageView message,
    required String newText,
  }) async {
    final conversationId = _conversationId;
    final trimmed = newText.trim();
    if (conversationId == null || trimmed.isEmpty || !message.isMine) {
      _logActionFailure(
        action: 'chat.edit',
        reason: 'validation_failed',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
          'isMine': message.isMine,
          'newText': trimmed,
        },
      );
      return false;
    }

    _logActionStart('chat.edit', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
      'newText': trimmed,
    });
    emit(state.copyWith(clearError: true));
    try {
      final editCiphertext = await _cryptoEngine.encrypt(
        plaintext: trimmed,
        peerDeviceId: _peerDeviceId(conversationId),
      );
      final result = await _messageRepository.editMessage(
        conversationId: conversationId,
        messageId: message.id,
        editCiphertext: editCiphertext,
      );
      if (result is FailureResult<void>) {
        _logFailureResult(
          result,
          event: 'chat.edit.failure',
          action: 'chat.edit',
          metadata: <String, Object?>{
            'conversationId': conversationId,
            'messageId': message.id,
          },
        );
        emit(state.copyWith(errorMessage: result.failure.message));
        return false;
      }
      _logActionSuccess('chat.edit', <String, Object?>{
        'conversationId': conversationId,
        'messageId': message.id,
      });
      return true;
    } catch (error) {
      AppLogger.error(
        'Edit message failed',
        error,
        StackTrace.current,
        event: 'chat.edit.exception',
        action: 'chat.edit',
        source: 'ChatThreadCubit',
        operation: 'editMessage',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
        },
      );
      emit(state.copyWith(errorMessage: error.toString()));
      return false;
    }
  }

  Future<bool> deleteMessageForEveryone(ChatMessageView message) async {
    final conversationId = _conversationId;
    if (conversationId == null || !message.isMine) {
      _logActionFailure(
        action: 'chat.delete_for_everyone',
        reason: 'validation_failed',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
          'isMine': message.isMine,
        },
      );
      return false;
    }

    _logActionStart('chat.delete_for_everyone', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
    });
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.deleteMessageForEveryone(
      conversationId: conversationId,
      messageId: message.id,
    );
    if (result is FailureResult<void>) {
      _logFailureResult(
        result,
        event: 'chat.delete_for_everyone.failure',
        action: 'chat.delete_for_everyone',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
        },
      );
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    _logActionSuccess('chat.delete_for_everyone', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
    });
    return true;
  }

  Future<bool> deleteMessageForMe(ChatMessageView message) async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      _logActionFailure(
        action: 'chat.delete_for_me',
        reason: 'validation_failed',
        metadata: <String, Object?>{'messageId': message.id},
      );
      return false;
    }

    _logActionStart('chat.delete_for_me', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
    });
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.deleteMessageForMe(
      conversationId: conversationId,
      messageId: message.id,
    );
    if (result is FailureResult<void>) {
      _logFailureResult(
        result,
        event: 'chat.delete_for_me.failure',
        action: 'chat.delete_for_me',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
        },
      );
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    _logActionSuccess('chat.delete_for_me', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
    });
    return true;
  }

  Future<bool> forwardMessage({
    required ChatMessageView message,
    required String targetConversationId,
  }) async {
    final text = message.text.trim();
    if (text.isEmpty) {
      return false;
    }

    emit(state.copyWith(sending: true, clearError: true));
    final result = await _sendTextMessage(
      SendTextMessageParams(
        conversationId: targetConversationId,
        senderId: _currentUserId,
        plaintext: text,
        peerDeviceId: _peerDeviceId(targetConversationId),
        messageType: message.type,
      ),
    );

    if (result is FailureResult<void>) {
      emit(
        state.copyWith(sending: false, errorMessage: result.failure.message),
      );
      return false;
    }

    emit(state.copyWith(sending: false, clearError: true));
    return true;
  }

  Future<bool> setMessageReaction({
    required ChatMessageView message,
    String? emoji,
  }) async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      _logActionFailure(
        action: 'chat.reaction',
        reason: 'validation_failed',
        metadata: <String, Object?>{'messageId': message.id},
      );
      return false;
    }
    _logActionStart('chat.reaction', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
      'emoji': emoji,
    });
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.setMessageReaction(
      conversationId: conversationId,
      messageId: message.id,
      userId: _currentUserId,
      emoji: emoji,
    );
    if (result is FailureResult<void>) {
      _logFailureResult(
        result,
        event: 'chat.reaction.failure',
        action: 'chat.reaction',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
          'emoji': emoji,
        },
      );
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    _logActionSuccess('chat.reaction', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
    });
    return true;
  }

  Future<bool> toggleMessageStar(ChatMessageView message) async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      return false;
    }
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.setMessageStarred(
      conversationId: conversationId,
      messageId: message.id,
      userId: _currentUserId,
      starred: !message.isStarred,
    );
    if (result is FailureResult<void>) {
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    return true;
  }

  Future<bool> toggleMessagePin(ChatMessageView message) async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      _logActionFailure(
        action: 'chat.pin',
        reason: 'validation_failed',
        metadata: <String, Object?>{'messageId': message.id},
      );
      return false;
    }
    if (!message.isPinned) {
      final currentlyPinned = state.messages
          .where((item) => item.isPinned)
          .length;
      if (currentlyPinned >= 3) {
        _logActionFailure(
          action: 'chat.pin',
          reason: 'limit_reached',
          metadata: <String, Object?>{
            'conversationId': conversationId,
            'messageId': message.id,
            'currentlyPinned': currentlyPinned,
          },
        );
        emit(
          state.copyWith(
            errorMessage:
                'You can pin up to 3 messages. Unpin one to add another.',
          ),
        );
        return false;
      }
    }
    _logActionStart('chat.pin', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
      'targetPinned': !message.isPinned,
    });
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.setMessagePinned(
      conversationId: conversationId,
      messageId: message.id,
      userId: _currentUserId,
      pinned: !message.isPinned,
    );
    if (result is FailureResult<void>) {
      _logFailureResult(
        result,
        event: 'chat.pin.failure',
        action: 'chat.pin',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageId': message.id,
          'targetPinned': !message.isPinned,
        },
      );
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    _logActionSuccess('chat.pin', <String, Object?>{
      'conversationId': conversationId,
      'messageId': message.id,
      'targetPinned': !message.isPinned,
    });
    return true;
  }

  Future<bool> clearConversation() async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      _logActionFailure(action: 'chat.clear', reason: 'validation_failed');
      return false;
    }
    _logActionStart('chat.clear', <String, Object?>{
      'conversationId': conversationId,
    });
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.clearConversationMessages(
      conversationId: conversationId,
    );
    if (result is FailureResult<void>) {
      _logFailureResult(
        result,
        event: 'chat.clear.failure',
        action: 'chat.clear',
        metadata: <String, Object?>{'conversationId': conversationId},
      );
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    _logActionSuccess('chat.clear', <String, Object?>{
      'conversationId': conversationId,
    });
    return true;
  }

  Future<ChatMessageView> _toMessageView(Message message) async {
    if (message.deletedForAllAt != null) {
      return ChatMessageView(
        id: message.id,
        senderId: message.senderId,
        type: message.type,
        text: 'This message was deleted',
        sentAt: message.clientTimestamp.toLocal(),
        isMine: message.senderId == _currentUserId,
        ack: _ackForMessage(message),
        replyToMessageId: message.replyToMessageId,
        editedAt: message.editedAt?.toLocal(),
        deletedForAllAt: message.deletedForAllAt?.toLocal(),
        isStarred: message.starredByUserIds.contains(_currentUserId),
        isPinned: message.pinnedByUserIds.contains(_currentUserId),
        reactionsByUser: message.reactionsByUser,
      );
    }

    final text = await _decryptMessageText(message);
    return ChatMessageView(
      id: message.id,
      senderId: message.senderId,
      type: message.type,
      text: text,
      sentAt: message.clientTimestamp.toLocal(),
      isMine: message.senderId == _currentUserId,
      ack: _ackForMessage(message),
      replyToMessageId: message.replyToMessageId,
      editedAt: message.editedAt?.toLocal(),
      deletedForAllAt: message.deletedForAllAt?.toLocal(),
      isStarred: message.starredByUserIds.contains(_currentUserId),
      isPinned: message.pinnedByUserIds.contains(_currentUserId),
      reactionsByUser: message.reactionsByUser,
    );
  }

  ChatMessageAck _ackForMessage(Message message) {
    if (message.senderId != _currentUserId) {
      return ChatMessageAck.sent;
    }

    final readByOthers = message.readByUserIds.any(
      (id) => id != _currentUserId,
    );
    if (readByOthers) {
      return ChatMessageAck.read;
    }

    final deliveredToOthers = message.deliveredToUserIds.any(
      (id) => id != _currentUserId,
    );
    if (deliveredToOthers) {
      return ChatMessageAck.delivered;
    }

    return ChatMessageAck.sent;
  }

  void _tryMarkConversationRead({
    required String conversationId,
    required List<Message> messages,
  }) {
    Message? latestUnreadIncoming;
    for (final message in messages.reversed) {
      final isUnreadIncoming =
          message.senderId != _currentUserId &&
          message.deletedForAllAt == null &&
          !message.readByUserIds.contains(_currentUserId);
      if (isUnreadIncoming) {
        latestUnreadIncoming = message;
        break;
      }
    }
    if (latestUnreadIncoming == null) {
      return;
    }
    if (_lastUnreadIncomingIdMarked == latestUnreadIncoming.id) {
      return;
    }

    final now = DateTime.now();
    final last = _lastMarkReadAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }

    if (_markReadInFlight) {
      _markReadQueued = true;
      return;
    }

    _markReadInFlight = true;
    _lastMarkReadAt = now;
    _lastUnreadIncomingIdMarked = latestUnreadIncoming.id;
    unawaited(
      _messageRepository
          .markConversationRead(
            conversationId: conversationId,
            userId: _currentUserId,
          )
          .whenComplete(() {
            _markReadInFlight = false;
            if (_markReadQueued) {
              _markReadQueued = false;
              _tryMarkConversationRead(
                conversationId: conversationId,
                messages: messages,
              );
            }
          }),
    );
  }

  void _enqueueSnapshot({
    required String conversationId,
    required List<Message> messages,
  }) {
    final wasQueued = _queuedSnapshot != null;
    _queuedSnapshot = messages;
    AppLogger.breadcrumb(
      wasQueued ? 'chat.snapshot.coalesced' : 'chat.snapshot.received',
      action: 'chat.snapshot',
      metadata: <String, Object?>{
        'conversationId': conversationId,
        'messageCount': messages.length,
        'processing': _processingSnapshots,
      },
    );
    if (_processingSnapshots) {
      return;
    }
    _processingSnapshots = true;
    unawaited(_drainSnapshots(conversationId));
  }

  Future<void> _drainSnapshots(String conversationId) async {
    try {
      while (true) {
        final messages = _queuedSnapshot;
        if (messages == null) {
          break;
        }
        _queuedSnapshot = null;
        final views = await _buildViewsChunked(
          conversationId: conversationId,
          messages: messages,
        );
        if (isClosed) {
          return;
        }
        emit(state.copyWith(messages: views, loading: false, clearError: true));
        _tryMarkConversationRead(
          conversationId: conversationId,
          messages: messages,
        );
      }
    } catch (error) {
      AppLogger.error(
        'Chat snapshot processing failed',
        error,
        StackTrace.current,
        event: 'chat.snapshot.failure',
        action: 'chat.snapshot',
        source: 'ChatThreadCubit',
        operation: 'drainSnapshots',
        metadata: <String, Object?>{'conversationId': conversationId},
      );
      if (!isClosed) {
        emit(state.copyWith(loading: false, errorMessage: error.toString()));
      }
    } finally {
      _processingSnapshots = false;
      if (_queuedSnapshot != null && !isClosed) {
        _enqueueSnapshot(
          conversationId: conversationId,
          messages: _queuedSnapshot!,
        );
      }
    }
  }

  Future<List<ChatMessageView>> _buildViewsChunked({
    required String conversationId,
    required List<Message> messages,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final views = <ChatMessageView>[];
    var chunkCount = 0;

    for (var start = 0; start < messages.length; start += _snapshotChunkSize) {
      final endExclusive = (start + _snapshotChunkSize < messages.length)
          ? start + _snapshotChunkSize
          : messages.length;
      final chunk = messages.sublist(start, endExclusive);
      final chunkViews = await Future.wait(chunk.map(_toMessageView));
      views.addAll(chunkViews);
      chunkCount++;
      if (endExclusive < messages.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final durationMs = DateTime.now()
        .toUtc()
        .difference(startedAt)
        .inMilliseconds;
    final shouldLog =
        durationMs >= 180 ||
        messages.length >= 120 ||
        _lastSnapshotPerfLogAt == null ||
        DateTime.now().toUtc().difference(_lastSnapshotPerfLogAt!) >=
            _snapshotPerfLogInterval;
    if (shouldLog) {
      _lastSnapshotPerfLogAt = DateTime.now().toUtc();
      AppLogger.info(
        'Chat snapshot processed',
        event: 'chat.snapshot.processed',
        action: 'chat.snapshot',
        metadata: <String, Object?>{
          'conversationId': conversationId,
          'messageCount': messages.length,
          'chunkCount': chunkCount,
          'durationMs': durationMs,
          'queuedAfterProcessing': _queuedSnapshot != null,
        },
      );
    }

    return views;
  }

  Future<String> _decryptMessageText(Message message) async {
    final cipher = message.ciphertext;
    final cached = _decryptCacheByCiphertext[cipher];
    if (cached != null) {
      return cached;
    }

    try {
      final plaintext = await _cryptoEngine.decrypt(
        ciphertext: cipher,
        peerDeviceId: _peerDeviceId(message.conversationId),
      );
      if (_decryptCacheByCiphertext.length > 400) {
        _decryptCacheByCiphertext.remove(_decryptCacheByCiphertext.keys.first);
      }
      _decryptCacheByCiphertext[cipher] = plaintext;
      return plaintext;
    } catch (_) {
      _logDecryptFallback(message);
      return cipher;
    }
  }

  void _logDecryptFallback(Message message) {
    final now = DateTime.now().toUtc();
    final last = _lastDecryptFallbackLogAt;
    if (last == null || now.difference(last) >= _decryptFallbackLogWindow) {
      AppLogger.warning(
        'Message decryption failed, showing ciphertext fallback',
        event: 'chat.decrypt.fallback',
        action: 'chat.decrypt',
        metadata: <String, Object?>{
          'conversationId': message.conversationId,
          'suppressedSinceLastLog': _suppressedDecryptFallbackCount,
        },
      );
      _lastDecryptFallbackLogAt = now;
      _suppressedDecryptFallbackCount = 0;
      return;
    }
    _suppressedDecryptFallbackCount++;
  }

  String _peerDeviceId(String conversationId) => 'peer-$conversationId';

  bool _allowSendNow() {
    final now = DateTime.now().toUtc();
    _recentSendAttempts.removeWhere(
      (attempt) => now.difference(attempt) > const Duration(seconds: 15),
    );
    if (_recentSendAttempts.length >= 8) {
      return false;
    }
    _recentSendAttempts.add(now);
    return true;
  }

  void _logActionStart(String action, [Map<String, Object?>? metadata]) {
    AppLogger.breadcrumb(
      '${action.replaceAll('.', '_')}.start',
      action: action,
      metadata: metadata,
    );
  }

  void _logActionSuccess(String action, [Map<String, Object?>? metadata]) {
    AppLogger.info(
      'Action succeeded',
      event: '${action.replaceAll('.', '_')}.success',
      action: action,
      metadata: metadata,
    );
  }

  void _logActionFailure({
    required String action,
    required String reason,
    Map<String, Object?>? metadata,
  }) {
    AppLogger.warning(
      'Action failed',
      event: '${action.replaceAll('.', '_')}.failure',
      action: action,
      metadata: <String, Object?>{'reason': reason, ...?metadata},
    );
  }

  void _logFailureResult(
    FailureResult<void> result, {
    required String event,
    required String action,
    Map<String, Object?>? metadata,
  }) {
    result.logIfFailure(
      event: event,
      action: action,
      source: 'ChatThreadCubit',
      metadata: metadata,
    );
  }

  @override
  Future<void> close() async {
    await _messagesSubscription?.cancel();
    return super.close();
  }
}
