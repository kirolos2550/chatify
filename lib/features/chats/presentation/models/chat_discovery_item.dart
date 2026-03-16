import 'package:chatify/core/domain/entities/conversation.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';

enum ChatListFilter { all, unread, favorites }

class ChatDiscoveryItem {
  const ChatDiscoveryItem({
    required this.title,
    required this.subtitle,
    required this.conversationId,
    required this.trailing,
    this.searchPhone,
    this.unreadCount = 0,
    this.isArchived = false,
    this.isPinned = false,
    this.isFavorite = false,
    this.lists = const [],
  });

  final String title;
  final String subtitle;
  final String conversationId;
  final String trailing;
  final String? searchPhone;
  final int unreadCount;
  final bool isArchived;
  final bool isPinned;
  final bool isFavorite;
  final List<String> lists;

  ChatDiscoveryItem copyWith({
    String? title,
    String? subtitle,
    String? conversationId,
    String? trailing,
    String? searchPhone,
    int? unreadCount,
    bool? isArchived,
    bool? isPinned,
    bool? isFavorite,
    List<String>? lists,
  }) {
    return ChatDiscoveryItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      conversationId: conversationId ?? this.conversationId,
      trailing: trailing ?? this.trailing,
      searchPhone: searchPhone ?? this.searchPhone,
      unreadCount: unreadCount ?? this.unreadCount,
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      lists: lists ?? this.lists,
    );
  }
}

ChatDiscoveryItem mapConversationToChatDiscoveryItem(
  Conversation conversation,
) {
  final searchPhone = conversation.searchPhone?.trim();
  final resolvedTitle =
      (conversation.title != null && conversation.title!.trim().isNotEmpty)
      ? conversation.title!.trim()
      : conversation.type == ConversationType.group
      ? 'Group ${conversation.id.substring(0, 6)}'
      : (searchPhone != null && searchPhone.isNotEmpty)
      ? searchPhone
      : 'Direct chat';
  final resolvedSubtitle = conversation.type == ConversationType.group
      ? 'Group conversation'
      : (searchPhone != null &&
            searchPhone.isNotEmpty &&
            searchPhone != resolvedTitle)
      ? searchPhone
      : 'Private conversation';

  return ChatDiscoveryItem(
    title: resolvedTitle,
    subtitle: resolvedSubtitle,
    conversationId: conversation.id,
    trailing: formatConversationTime(conversation.updatedAt),
    searchPhone: searchPhone,
    unreadCount: conversation.unreadCount,
    isArchived: conversation.isArchived,
    isPinned: conversation.isPinned,
    isFavorite: conversation.isFavorite,
    lists: conversation.lists,
  );
}

String formatConversationTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

List<ChatDiscoveryItem> filterChatDiscoveryItems({
  required List<ChatDiscoveryItem> items,
  String query = '',
  ChatListFilter filter = ChatListFilter.all,
  String? list,
}) {
  final trimmedList = list?.trim();
  return items
      .where((item) {
        if (!matchesChatQuery(item, query)) {
          return false;
        }
        if (trimmedList != null &&
            trimmedList.isNotEmpty &&
            !item.lists.any(
              (candidate) =>
                  candidate.toLowerCase() == trimmedList.toLowerCase(),
            )) {
          return false;
        }
        return switch (filter) {
          ChatListFilter.all => true,
          ChatListFilter.unread => item.unreadCount > 0,
          ChatListFilter.favorites => item.isFavorite,
        };
      })
      .toList(growable: false);
}

bool matchesChatQuery(ChatDiscoveryItem item, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return true;
  }
  final normalizedDigits = _digitsOnly(normalized);
  final fields = <String>[
    item.title,
    item.subtitle,
    item.conversationId,
    if (item.searchPhone != null) item.searchPhone!,
    ...item.lists,
  ];

  for (final field in fields) {
    final candidate = field.trim().toLowerCase();
    if (candidate.contains(normalized)) {
      return true;
    }
    if (normalizedDigits.isNotEmpty &&
        _digitsOnly(candidate).contains(normalizedDigits)) {
      return true;
    }
  }
  return false;
}

List<String> collectChatLists(Iterable<ChatDiscoveryItem> items) {
  final deduped = <String, String>{};
  for (final item in items) {
    for (final list in item.lists) {
      final trimmed = list.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      deduped.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
    }
  }
  final output = deduped.values.toList(growable: false);
  output.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );
  return output;
}

List<String> parseChatLists(String raw) {
  final deduped = <String, String>{};
  for (final part in raw.split(RegExp(r'[,;\n]'))) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    deduped.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
  }
  return deduped.values.toList(growable: false);
}

String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');
