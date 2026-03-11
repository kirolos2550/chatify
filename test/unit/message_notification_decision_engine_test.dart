import 'package:chatify/core/notifications/message_notification_decision_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageNotificationDecisionEngine', () {
    test('does not emit on first snapshot for a conversation', () {
      final engine = MessageNotificationDecisionEngine();

      final shouldEmit = engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      expect(shouldEmit, isFalse);
    });

    test('emits for new incoming message after initial prime', () {
      final engine = MessageNotificationDecisionEngine();

      engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      final shouldEmit = engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm2',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      expect(shouldEmit, isTrue);
    });

    test('does not emit for same message id', () {
      final engine = MessageNotificationDecisionEngine();

      engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      final shouldEmit = engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      expect(shouldEmit, isFalse);
    });

    test('does not emit for messages sent by current user', () {
      final engine = MessageNotificationDecisionEngine();

      engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      final shouldEmit = engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm2',
        senderId: 'me',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      expect(shouldEmit, isFalse);
    });

    test('does not emit when same conversation is open', () {
      final engine = MessageNotificationDecisionEngine();

      engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      final shouldEmit = engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm2',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: true,
      );

      expect(shouldEmit, isFalse);
    });

    test('emits after priming empty conversation when incoming arrives', () {
      final engine = MessageNotificationDecisionEngine();
      engine.primeConversation('c1');

      final shouldEmit = engine.shouldEmitForLatestMessage(
        conversationId: 'c1',
        messageId: 'm2',
        senderId: 'peer',
        currentUserId: 'me',
        isConversationOpen: false,
      );

      expect(shouldEmit, isTrue);
    });
  });
}
