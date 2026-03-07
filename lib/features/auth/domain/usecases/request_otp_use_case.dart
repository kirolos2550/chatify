import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:injectable/injectable.dart';

class RequestOtpParams {
  const RequestOtpParams(this.phoneNumber);
  final String phoneNumber;
}

@injectable
class RequestOtpUseCase implements UseCase<Result<String>, RequestOtpParams> {
  RequestOtpUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Result<String>> call(RequestOtpParams params) {
    return _repository.requestOtp(phoneNumber: params.phoneNumber);
  }
}
