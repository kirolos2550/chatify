import 'package:chatify/features/chats/presentation/models/chat_discovery_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchesChatQuery', () {
    const item = ChatDiscoveryItem(
      title: 'Mohamed Ali',
      subtitle: '+20 100 111 2223',
      conversationId: 'c_1',
      trailing: '10:42',
      searchPhone: '+20 100 111 2223',
      lists: ['Work', 'Urgent'],
    );

    test('matches title case-insensitively', () {
      expect(matchesChatQuery(item, 'mohamed'), isTrue);
      expect(matchesChatQuery(item, 'ALI'), isTrue);
    });

    test('matches phone digits regardless of formatting', () {
      expect(matchesChatQuery(item, '100111'), isTrue);
      expect(matchesChatQuery(item, '2223'), isTrue);
    });

    test('matches custom labels', () {
      expect(matchesChatQuery(item, 'urgent'), isTrue);
      expect(matchesChatQuery(item, 'family'), isFalse);
    });
  });

  group('filterChatDiscoveryItems', () {
    const items = [
      ChatDiscoveryItem(
        title: 'Family',
        subtitle: 'Group conversation',
        conversationId: 'c_family',
        trailing: '09:15',
        unreadCount: 4,
        lists: ['Family'],
      ),
      ChatDiscoveryItem(
        title: 'Nora',
        subtitle: '+20 122 333 4444',
        conversationId: 'c_nora',
        trailing: '08:00',
        isFavorite: true,
        lists: ['Work'],
      ),
    ];

    test('filters unread conversations', () {
      final filtered = filterChatDiscoveryItems(
        items: items,
        filter: ChatListFilter.unread,
      );

      expect(filtered.map((item) => item.conversationId), ['c_family']);
    });

    test('combines favorites with category filtering', () {
      final filtered = filterChatDiscoveryItems(
        items: items,
        filter: ChatListFilter.favorites,
        list: 'Work',
      );

      expect(filtered.map((item) => item.conversationId), ['c_nora']);
    });
  });

  test('parseChatLists trims and deduplicates lists', () {
    expect(
      parseChatLists(' Work, family ; work\nUrgent '),
      ['Work', 'family', 'Urgent'],
    );
  });
}
