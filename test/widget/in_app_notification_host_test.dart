import 'package:chatify/core/notifications/in_app_notification_center.dart';
import 'package:chatify/core/notifications/in_app_notification_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows top popup with sender and preview', (tester) async {
    final center = InAppNotificationCenter();

    await tester.pumpWidget(
      MaterialApp(
        home: InAppNotificationHost(
          notificationCenter: center,
          displayDuration: const Duration(seconds: 10),
          child: const Scaffold(body: Center(child: Text('Home'))),
        ),
      ),
    );

    center.publish(
      InAppMessageNotification(
        conversationId: 'c1',
        messageId: 'm1',
        senderId: 'u2',
        senderName: 'Alice',
        preview: 'Hello from popup',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Hello from popup'), findsOneWidget);

    final dy = tester.getTopLeft(find.text('Alice')).dy;
    expect(dy, lessThan(140));
  });

  testWidgets('tapping popup opens target notification callback', (
    tester,
  ) async {
    final center = InAppNotificationCenter();
    String? openedConversationId;

    await tester.pumpWidget(
      MaterialApp(
        home: InAppNotificationHost(
          notificationCenter: center,
          displayDuration: const Duration(seconds: 10),
          onNotificationTap: (notification) async {
            openedConversationId = notification.conversationId;
          },
          child: const Scaffold(body: Center(child: Text('Home'))),
        ),
      ),
    );

    center.publish(
      InAppMessageNotification(
        conversationId: 'c-target',
        messageId: 'm1',
        senderId: 'u2',
        senderName: 'Bob',
        preview: 'Tap me',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Tap me'), findsOneWidget);

    await tester.tap(find.text('Tap me'));
    await tester.pump();

    expect(openedConversationId, 'c-target');
  });
}
