import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:equatable/equatable.dart';

class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.type,
    required this.createdAt,
    this.unreadCount = 0,
    this.isArchived = false,
    this.isPinned = false,
    this.isFavorite = false,
    this.lists = const [],
    this.title,
    this.avatarUrl,
    this.searchPhone,
    this.lastMessageId,
    this.updatedAt,
  });

  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarUrl;
  final String? searchPhone;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? lastMessageId;
  final int unreadCount;
  final bool isArchived;
  final bool isPinned;
  final bool isFavorite;
  final List<String> lists;

  @override
  List<Object?> get props => [
    id,
    type,
    title,
    avatarUrl,
    searchPhone,
    createdAt,
    updatedAt,
    lastMessageId,
    unreadCount,
    isArchived,
    isPinned,
    isFavorite,
    lists,
  ];
}
