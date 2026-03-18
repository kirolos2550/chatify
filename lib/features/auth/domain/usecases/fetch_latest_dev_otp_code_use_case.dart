import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:injectable/injectable.dart';

class FetchLatestDevOtpCodeParams {
  const FetchLatestDevOtpCodeParams({
    required this.phoneNumber,
    this.otpSessionId,
  });

  final String phoneNumber;
  final String? otpSessionId;
}

@injectable
class FetchLatestDevOtpCodeUseCase
    implements UseCase<Result<String?>, FetchLatestDevOtpCodeParams> {
  FetchLatestDevOtpCodeUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Result<String?>> call(FetchLatestDevOtpCodeParams params) {
    return _repository.fetchLatestDevOtpCode(
      phoneNumber: params.phoneNumber,
      otpSessionId: params.otpSessionId,
    );
  }
}
