import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:injectable/injectable.dart';

class VerifyOtpParams {
  const VerifyOtpParams({required this.verificationId, required this.code});

  final String verificationId;
  final String code;
}

@injectable
class VerifyOtpUseCase implements UseCase<Result<void>, VerifyOtpParams> {
  VerifyOtpUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Result<void>> call(VerifyOtpParams params) {
    return _repository.verifyOtp(
      verificationId: params.verificationId,
      otpCode: params.code,
    );
  }
}
