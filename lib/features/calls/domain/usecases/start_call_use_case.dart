import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/call_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:injectable/injectable.dart';

class StartCallParams {
  const StartCallParams({required this.participantIds, required this.type});

  final List<String> participantIds;
  final CallType type;
}

@injectable
class StartCallUseCase
    implements UseCase<Result<CallSession>, StartCallParams> {
  StartCallUseCase(this._repository);

  final CallRepository _repository;

  @override
  Future<Result<CallSession>> call(StartCallParams params) {
    return _repository.startCall(
      participantIds: params.participantIds,
      type: params.type,
    );
  }
}
