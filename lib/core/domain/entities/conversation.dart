import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:equatable/equatable.dart';

class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.type,
    required this.createdAt,
    this.isArchived = false,
    this.title,
    this.avatarUrl,
    this.lastMessageId,
    this.updatedAt,
  });

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? lastMessageId;
  final bool isArchived;

  @override
  List<Object?> get props => [
    id,
    type,
    title,
    avatarUrl,
    createdAt,
    updatedAt,
    lastMessageId,
    isArchived,
  ];
}
