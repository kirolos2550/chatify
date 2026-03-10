import 'dart:io';

import 'package:chatify/app/app.dart';
import 'package:chatify/app/flavor.dart';
import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await AppLogger.flushAndClose();
  });

  tearDown(() async {
    await AppLogger.flushAndClose();
    AppRouter.router.go('/auth');
  });

  testWidgets('route transition events are logged to debug session file', (
    tester,
  ) async {
    final rootDir = await Directory.systemTemp.createTemp('chatify_route_log_');
    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    await AppLogger.initDebugSession(
      flavor: 'dev',
      buildMode: 'debug',
      platform: 'android',
      logDirectoryPathProvider: () async => rootDir.path,
      clock: () => DateTime.utc(2026, 3, 10, 14, 0, 0),
    );

    AppRouter.router.go('/auth');
    AppRouter.enableRouteTracing();

    await tester.pumpWidget(const ChatifyApp(flavor: AppFlavor.dev));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Continue in demo mode').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Settings').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final path = AppLogger.currentSessionLogPath;
    expect(path, isNotNull);
    await AppLogger.flushAndClose();

    final content = await File(path!).readAsString();
    expect(content, contains('route.transition'));
    expect(content, contains('/home/chats'));
    expect(content, contains('/home/settings'));
  });
}
