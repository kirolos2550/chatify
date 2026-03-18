import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();

  Future<Result<String>> requestOtp({required String phoneNumber});

  Future<Result<void>> verifyOtp({
    required String otpSessionId,
    required String otpCode,
  });

  Future<Result<String?>> fetchLatestDevOtpCode({
    required String phoneNumber,
    String? otpSessionId,
  });

  Future<Result<void>> setTwoStepPin({required String pin});

  Future<Result<void>> updateProfile({
    required String displayName,
    String? about,
    String? avatarUrl,
  });

  Future<Result<void>> signOut();
}
