import 'dart:async';

import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/message.dart';
import 'package:chatify/core/domain/repositories/message_repository.dart';

class InMemoryMessageRepository implements MessageRepository {
  final Map<String, List<Message>> _messagesByConversation = {};
  final Map<String, StreamController<List<Message>>> _controllers = {};

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    final controller = _controllerFor(conversationId);
    controller.add(List<Message>.unmodifiable(_messagesFor(conversationId)));
    return controller.stream;
  }

  @override
  Future<Result<void>> sendMessage({
    required String conversationId,
    required Message message,
  }) async {
    try {
      final list = _messagesFor(conversationId);
      final index = list.indexWhere((item) => item.id == message.id);
      if (index >= 0) {
        list[index] = message;
      } else {
        list.add(message);
      }
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  @override
  Future<Result<void>> editMessage({
    required String conversationId,
    required String messageId,
    required String editCiphertext,
  }) async {
    return _updateMessage(
      conversationId: conversationId,
      messageId: messageId,
      update: (current) => current.copyWith(
        ciphertext: editCiphertext,
        editedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<Result<void>> deleteMessageForEveryone({
    required String conversationId,
    required String messageId,
  }) async {
    return _updateMessage(
      conversationId: conversationId,
      messageId: messageId,
      update: (current) => current.copyWith(
        ciphertext: '',
        deletedForAllAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<Result<void>> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      final list = _messagesFor(conversationId);
      list.removeWhere((item) => item.id == messageId);
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  @override
  Future<Result<void>> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final list = _messagesFor(conversationId);
      var changed = false;
      for (var i = 0; i < list.length; i++) {
        final current = list[i];
        if (current.senderId == userId || current.deletedForAllAt != null) {
          continue;
        }
        final delivered = current.deliveredToUserIds.toSet();
        final read = current.readByUserIds.toSet();
        final didChange = delivered.add(userId) | read.add(userId);
        if (!didChange) {
          continue;
        }
        changed = true;
        list[i] = current.copyWith(
          deliveredToUserIds: delivered.toList(growable: false),
          readByUserIds: read.toList(growable: false),
        );
      }
      if (changed) {
        _emit(conversationId);
      }
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  @override
  Future<Result<void>> clearConversationMessages({
    required String conversationId,
  }) async {
    try {
      _messagesByConversation[conversationId] = <Message>[];
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  @override
  Future<Result<void>> setMessageReaction({
    required String conversationId,
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    return _updateMessage(
      conversationId: conversationId,
      messageId: messageId,
      update: (current) {
        final reactions = Map<String, String>.from(current.reactionsByUser);
        final normalizedEmoji = emoji?.trim();
        if (normalizedEmoji == null || normalizedEmoji.isEmpty) {
          reactions.remove(userId);
        } else {
          reactions[userId] = normalizedEmoji;
        }
        return current.copyWith(reactionsByUser: reactions);
      },
    );
  }

  @override
  Future<Result<void>> setMessageStarred({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool starred,
  }) async {
    return _updateMessage(
      conversationId: conversationId,
      messageId: messageId,
      update: (current) {
        final starredBy = current.starredByUserIds.toSet();
        if (starred) {
          starredBy.add(userId);
        } else {
          starredBy.remove(userId);
        }
        return current.copyWith(
          starredByUserIds: starredBy.toList(growable: false),
        );
      },
    );
  }

  @override
  Future<Result<void>> setMessagePinned({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool pinned,
  }) async {
    return _updateMessage(
      conversationId: conversationId,
      messageId: messageId,
      update: (current) {
        final pinnedBy = current.pinnedByUserIds.toSet();
        if (pinned) {
          pinnedBy.add(userId);
        } else {
          pinnedBy.remove(userId);
        }
        return current.copyWith(
          pinnedByUserIds: pinnedBy.toList(growable: false),
        );
      },
    );
  }

  List<Message> _messagesFor(String conversationId) {
    return _messagesByConversation.putIfAbsent(
      conversationId,
      () => <Message>[],
    );
  }

  StreamController<List<Message>> _controllerFor(String conversationId) {
    return _controllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );
  }

  Future<Result<void>> _updateMessage({
    required String conversationId,
    required String messageId,
    required Message Function(Message current) update,
  }) async {
    try {
      final list = _messagesFor(conversationId);
      final index = list.indexWhere((item) => item.id == messageId);
      if (index < 0) {
        return const FailureResult(Failure('Message not found'));
      }
      list[index] = update(list[index]);
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  void _emit(String conversationId) {
    final List<Message> messages = List<Message>.unmodifiable(
      _messagesFor(conversationId),
    );
    _controllerFor(conversationId).add(messages);
  }
}
