class MessageNotificationDecisionEngine {
  final Set<String> _primedConversationIds = <String>{};
  final Map<String, String> _lastMessageIdByConversation = <String, String>{};

  void primeConversation(String conversationId, {String? latestMessageId}) {
    _primedConversationIds.add(conversationId);
    if (latestMessageId != null && latestMessageId.isNotEmpty) {
      _lastMessageIdByConversation[conversationId] = latestMessageId;
    }
  }

  void clearInactiveConversations(Set<String> activeConversationIds) {
    _primedConversationIds.removeWhere(
      (conversationId) => !activeConversationIds.contains(conversationId),
    );
    _lastMessageIdByConversation.removeWhere(
      (conversationId, _) => !activeConversationIds.contains(conversationId),
    );
  }

  void reset() {
    _primedConversationIds.clear();
    _lastMessageIdByConversation.clear();
  }

  bool shouldEmitForLatestMessage({
    required String conversationId,
    required String messageId,
    required String senderId,
    required String currentUserId,
    required bool isConversationOpen,
  }) {
    if (conversationId.isEmpty || messageId.isEmpty) {
      return false;
    }

    final isFirstSnapshot = !_primedConversationIds.contains(conversationId);
    if (isFirstSnapshot) {
      _primedConversationIds.add(conversationId);
      _lastMessageIdByConversation[conversationId] = messageId;
      return false;
    }

    final previousMessageId = _lastMessageIdByConversation[conversationId];
    if (previousMessageId == messageId) {
      return false;
    }
    _lastMessageIdByConversation[conversationId] = messageId;

    if (senderId == currentUserId) {
      return false;
    }

    if (isConversationOpen) {
      return false;
    }

    return true;
  }
}
