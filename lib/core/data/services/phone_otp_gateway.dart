import 'package:chatify/core/common/result.dart';

class PhoneOtpRequestResult {
  const PhoneOtpRequestResult({
    required this.otpSessionId,
    required this.autoVerified,
  });

  const PhoneOtpRequestResult.codeSent(String otpSessionId)
    : this(otpSessionId: otpSessionId, autoVerified: false);

  const PhoneOtpRequestResult.autoVerified()
    : this(otpSessionId: '', autoVerified: true);

  final String otpSessionId;
  final bool autoVerified;
}

abstract interface class PhoneOtpGateway {
  Future<Result<PhoneOtpRequestResult>> requestCode({
    required String phoneNumber,
  });

  Future<Result<void>> verifyCode({
    required String otpSessionId,
    required String otpCode,
  });

  Future<Result<String?>> fetchLatestDevCode({
    required String phoneNumber,
    String? otpSessionId,
  });
}
