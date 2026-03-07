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
    try {
      final list = _messagesFor(conversationId);
      final index = list.indexWhere((item) => item.id == messageId);
      if (index < 0) {
        return const FailureResult(Failure('Message not found'));
      }
      final current = list[index];
      list[index] = Message(
        id: current.id,
        conversationId: current.conversationId,
        senderId: current.senderId,
        type: current.type,
        ciphertext: editCiphertext,
        clientTimestamp: current.clientTimestamp,
        serverSeq: current.serverSeq,
        editedAt: DateTime.now().toUtc(),
        deletedForAllAt: current.deletedForAllAt,
        deletedForUserIds: current.deletedForUserIds,
        deliveredToUserIds: current.deliveredToUserIds,
        readByUserIds: current.readByUserIds,
        localStatus: current.localStatus,
        deviceId: current.deviceId,
        replyToMessageId: current.replyToMessageId,
        e2eeVersion: current.e2eeVersion,
        starredByUserIds: current.starredByUserIds,
        reactionsByUser: current.reactionsByUser,
      );
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  @override
  Future<Result<void>> deleteMessageForEveryone({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      final list = _messagesFor(conversationId);
      final index = list.indexWhere((item) => item.id == messageId);
      if (index < 0) {
        return const FailureResult(Failure('Message not found'));
      }
      final current = list[index];
      list[index] = Message(
        id: current.id,
        conversationId: current.conversationId,
        senderId: current.senderId,
        type: current.type,
        ciphertext: '',
        clientTimestamp: current.clientTimestamp,
        serverSeq: current.serverSeq,
        editedAt: current.editedAt,
        deletedForAllAt: DateTime.now().toUtc(),
        deletedForUserIds: current.deletedForUserIds,
        deliveredToUserIds: current.deliveredToUserIds,
        readByUserIds: current.readByUserIds,
        localStatus: current.localStatus,
        deviceId: current.deviceId,
        replyToMessageId: current.replyToMessageId,
        e2eeVersion: current.e2eeVersion,
        starredByUserIds: current.starredByUserIds,
        reactionsByUser: current.reactionsByUser,
      );
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
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
        list[i] = Message(
          id: current.id,
          conversationId: current.conversationId,
          senderId: current.senderId,
          type: current.type,
          ciphertext: current.ciphertext,
          clientTimestamp: current.clientTimestamp,
          serverSeq: current.serverSeq,
          editedAt: current.editedAt,
          deletedForAllAt: current.deletedForAllAt,
          deletedForUserIds: current.deletedForUserIds,
          deliveredToUserIds: delivered.toList(growable: false),
          readByUserIds: read.toList(growable: false),
          localStatus: current.localStatus,
          deviceId: current.deviceId,
          replyToMessageId: current.replyToMessageId,
          e2eeVersion: current.e2eeVersion,
          starredByUserIds: current.starredByUserIds,
          reactionsByUser: current.reactionsByUser,
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
    try {
      final list = _messagesFor(conversationId);
      final index = list.indexWhere((item) => item.id == messageId);
      if (index < 0) {
        return const FailureResult(Failure('Message not found'));
      }
      final current = list[index];
      final reactions = Map<String, String>.from(current.reactionsByUser);
      final normalizedEmoji = emoji?.trim();
      if (normalizedEmoji == null || normalizedEmoji.isEmpty) {
        reactions.remove(userId);
      } else {
        reactions[userId] = normalizedEmoji;
      }
      list[index] = Message(
        id: current.id,
        conversationId: current.conversationId,
        senderId: current.senderId,
        type: current.type,
        ciphertext: current.ciphertext,
        clientTimestamp: current.clientTimestamp,
        serverSeq: current.serverSeq,
        editedAt: current.editedAt,
        deletedForAllAt: current.deletedForAllAt,
        deletedForUserIds: current.deletedForUserIds,
        deliveredToUserIds: current.deliveredToUserIds,
        readByUserIds: current.readByUserIds,
        localStatus: current.localStatus,
        deviceId: current.deviceId,
        replyToMessageId: current.replyToMessageId,
        e2eeVersion: current.e2eeVersion,
        starredByUserIds: current.starredByUserIds,
        reactionsByUser: reactions,
      );
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
  }

  @override
  Future<Result<void>> setMessageStarred({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool starred,
  }) async {
    try {
      final list = _messagesFor(conversationId);
      final index = list.indexWhere((item) => item.id == messageId);
      if (index < 0) {
        return const FailureResult(Failure('Message not found'));
      }
      final current = list[index];
      final starredBy = current.starredByUserIds.toSet();
      if (starred) {
        starredBy.add(userId);
      } else {
        starredBy.remove(userId);
      }
      list[index] = Message(
        id: current.id,
        conversationId: current.conversationId,
        senderId: current.senderId,
        type: current.type,
        ciphertext: current.ciphertext,
        clientTimestamp: current.clientTimestamp,
        serverSeq: current.serverSeq,
        editedAt: current.editedAt,
        deletedForAllAt: current.deletedForAllAt,
        deletedForUserIds: current.deletedForUserIds,
        deliveredToUserIds: current.deliveredToUserIds,
        readByUserIds: current.readByUserIds,
        localStatus: current.localStatus,
        deviceId: current.deviceId,
        replyToMessageId: current.replyToMessageId,
        e2eeVersion: current.e2eeVersion,
        starredByUserIds: starredBy.toList(growable: false),
        reactionsByUser: current.reactionsByUser,
      );
      _emit(conversationId);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(error.toString()));
    }
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

  void _emit(String conversationId) {
    final List<Message> messages = List<Message>.unmodifiable(
      _messagesFor(conversationId),
    );
    _controllerFor(conversationId).add(messages);
  }
}
