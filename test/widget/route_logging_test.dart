import 'dart:io';

import 'package:chatify/app/app.dart';
import 'package:chatify/app/flavor.dart';
import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    final rootDir = Directory(
      p.join(
        Directory.systemTemp.path,
        'chatify_route_log_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (rootDir.existsSync()) {
        try {
          rootDir.deleteSync(recursive: true);
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    });

    await tester.runAsync(() async {
      await AppLogger.initDebugSession(
        flavor: 'dev',
        buildMode: 'debug',
        platform: 'android',
        logDirectoryPathProvider: () async => rootDir.path,
        clock: () => DateTime.utc(2026, 3, 10, 14, 0, 0),
      );
    });

    await tester.pumpWidget(const ChatifyApp(flavor: AppFlavor.dev));
    await tester.pump(const Duration(milliseconds: 300));
    AppRouter.router.go('/auth');
    AppRouter.enableRouteTracing();
    await tester.pump();

    AppRouter.router.go('/home/chats');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    AppRouter.router.go('/home/settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final path = AppLogger.currentSessionLogPath;
    expect(path, isNotNull);
    await tester.runAsync(() async {
      await AppLogger.flushAndClose();
    });

    final content = await tester.runAsync(() => File(path!).readAsString());
    expect(content, isNotNull);
    expect(content, contains('route.transition'));
    expect(content, contains('/home/chats'));
    expect(content, contains('/home/settings'));
  });
}
