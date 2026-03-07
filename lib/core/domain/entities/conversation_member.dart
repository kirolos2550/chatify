import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:equatable/equatable.dart';

class ConversationMember extends Equatable {
  const ConversationMember({
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  final String conversationId;
  final String userId;
  final ConversationRole role;
  final DateTime joinedAt;

  @override
  List<Object?> get props => [conversationId, userId, role, joinedAt];
}
