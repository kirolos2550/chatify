import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/conversation.dart';

abstract interface class ConversationRepository {
  Stream<List<Conversation>> watchConversations();

  Future<Result<String>> createDirectConversation({required String peerUserId});

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
}
