import 'dart:io';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await AppLogger.flushAndClose();
  });

  tearDown(() async {
    await AppLogger.flushAndClose();
  });

  test('Result.onFailure invokes callback only for failures', () {
    const success = Success<int>(10);
    const failure = FailureResult<int>(Failure('boom'));
    var count = 0;

    success.onFailure((_) => count++);
    failure.onFailure((_) => count++);

    expect(count, 1);
  });

  test(
    'Result.logIfFailure writes failure event to debug session log',
    () async {
      final rootDir = await Directory.systemTemp.createTemp(
        'chatify_result_log_',
      );
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
        clock: () => DateTime.utc(2026, 3, 10, 13, 0, 0),
      );

      const FailureResult<void>(
        Failure('OTP verification failed', code: 'invalid-verification-code'),
      ).logIfFailure(
        event: 'auth.verify_otp.failure',
        action: 'auth.verify_otp',
        metadata: <String, Object?>{'otpCode': '123456'},
      );

      final path = AppLogger.currentSessionLogPath;
      expect(path, isNotNull);
      await AppLogger.flushAndClose();

      final content = await File(path!).readAsString();
      expect(content, contains('auth.verify_otp.failure'));
      expect(content, isNot(contains('123456')));
    },
  );
}
