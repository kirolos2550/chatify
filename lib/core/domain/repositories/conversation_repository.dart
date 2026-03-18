import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/conversation.dart';

abstract interface class ConversationRepository {
  Stream<List<Conversation>> watchConversations();
  Stream<List<String>> watchConversationLists();

  Future<Result<String>> createDirectConversation({required String peerUserId});
  Future<Result<String>> createConversationList({required String name});
  Future<Result<String>> renameConversationList({
    required String currentName,
    required String newName,
  });
  Future<Result<void>> deleteConversationList({required String name});
  Future<Result<void>> reorderConversationLists({
    required List<String> orderedNames,
  });

  Future<Result<String>> createGroup({
    required String title,
    required List<String> memberUserIds,
  });

  Future<Result<void>> deleteConversation({required String conversationId});

  Future<Result<void>> deleteConversationForMe({
    required String conversationId,
  });

  Future<Result<void>> setConversationArchived({
    required String conversationId,
    required bool archived,
  });

  Future<Result<void>> setConversationPinned({
    required String conversationId,
    required bool pinned,
  });

  Future<Result<void>> setConversationFavorite({
    required String conversationId,
    required bool favorite,
  });

  Future<Result<void>> setConversationLists({
    required String conversationId,
    required List<String> lists,
  });
}
