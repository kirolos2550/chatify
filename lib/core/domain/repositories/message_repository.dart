import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/message.dart';

abstract interface class MessageRepository {
  Stream<List<Message>> watchMessages(String conversationId);

  Future<Result<void>> sendMessage({
    required String conversationId,
    required Message message,
  });

  Future<Result<void>> editMessage({
    required String conversationId,
    required String messageId,
    required String editCiphertext,
  });

  Future<Result<void>> deleteMessageForEveryone({
    required String conversationId,
    required String messageId,
  });

  Future<Result<void>> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  });

  Future<Result<void>> markConversationRead({
    required String conversationId,
    required String userId,
  });

  Future<Result<void>> clearConversationMessages({
    required String conversationId,
  });
}
