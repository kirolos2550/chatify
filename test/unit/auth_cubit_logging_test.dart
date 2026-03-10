import 'dart:async';
import 'dart:io';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/features/auth/domain/usecases/request_otp_use_case.dart';
import 'package:chatify/features/auth/domain/usecases/verify_otp_use_case.dart';
import 'package:chatify/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AppUser?> authStateChanges() => const Stream<AppUser?>.empty();

  @override
  Future<Result<String>> requestOtp({required String phoneNumber}) async {
    return const Success('verification-id');
  }

  @override
  Future<Result<void>> setTwoStepPin({required String pin}) async {
    return const Success(null);
  }

  @override
  Future<Result<void>> signOut() async {
    return const Success(null);
  }

  @override
  Future<Result<void>> updateProfile({
    required String displayName,
    String? about,
    String? avatarUrl,
  }) async {
    return const Success(null);
  }

  @override
  Future<Result<void>> verifyOtp({
    required String verificationId,
    required String otpCode,
  }) async {
    return const Success(null);
  }
}

void main() {
  setUp(() async {
    await AppLogger.flushAndClose();
  });

  tearDown(() async {
    await AppLogger.flushAndClose();
  });

  test('AuthCubit logs OTP validation failures', () async {
    final rootDir = await Directory.systemTemp.createTemp('chatify_auth_log_');
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
      clock: () => DateTime.utc(2026, 3, 10, 15, 0, 0),
    );

    final repo = _FakeAuthRepository();
    final cubit = AuthCubit(RequestOtpUseCase(repo), VerifyOtpUseCase(repo));

    await cubit.verifyOtp('123');
    final path = AppLogger.currentSessionLogPath;
    expect(path, isNotNull);

    await cubit.close();
    await AppLogger.flushAndClose();

    final content = await File(path!).readAsString();
    expect(content, contains('auth.verify_otp.validation_failed'));
  });
}
