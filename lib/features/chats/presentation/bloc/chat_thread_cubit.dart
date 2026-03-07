import 'dart:async';

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
  DateTime? _lastMarkReadAt;
  String? _lastUnreadIncomingIdMarked;
  final Map<String, String> _decryptCacheByCiphertext = <String, String>{};

  void start(String conversationId) {
    _conversationId = conversationId;
    _queuedSnapshot = null;
    _processingSnapshots = false;
    _decryptCacheByCiphertext.clear();
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
              emit(
                state.copyWith(loading: false, errorMessage: error.toString()),
              );
            },
          );
    } catch (error) {
      emit(state.copyWith(loading: false, errorMessage: error.toString()));
    }
  }

  Future<bool> sendText(String rawText) async {
    return _sendTypedMessage(
      content: rawText.trim(),
      type: MessageType.text,
    );
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
      emit(
        state.copyWith(sending: false, errorMessage: result.failure.message),
      );
      return false;
    }

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
      return false;
    }

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
        emit(state.copyWith(errorMessage: result.failure.message));
        return false;
      }
      return true;
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
      return false;
    }
  }

  Future<bool> deleteMessageForEveryone(ChatMessageView message) async {
    final conversationId = _conversationId;
    if (conversationId == null || !message.isMine) {
      return false;
    }

    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.deleteMessageForEveryone(
      conversationId: conversationId,
      messageId: message.id,
    );
    if (result is FailureResult<void>) {
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
    return true;
  }

  Future<bool> deleteMessageForMe(ChatMessageView message) async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      return false;
    }

    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.deleteMessageForMe(
      conversationId: conversationId,
      messageId: message.id,
    );
    if (result is FailureResult<void>) {
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
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

  Future<bool> clearConversation() async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      return false;
    }
    emit(state.copyWith(clearError: true));
    final result = await _messageRepository.clearConversationMessages(
      conversationId: conversationId,
    );
    if (result is FailureResult<void>) {
      emit(state.copyWith(errorMessage: result.failure.message));
      return false;
    }
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
    _queuedSnapshot = messages;
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
        final views = await Future.wait(messages.map(_toMessageView));
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
      return cipher;
    }
  }

  String _peerDeviceId(String conversationId) => 'peer-$conversationId';

  @override
  Future<void> close() async {
    await _messagesSubscription?.cancel();
    return super.close();
  }
}
