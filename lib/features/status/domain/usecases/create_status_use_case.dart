import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/status_item.dart';
import 'package:chatify/core/domain/repositories/status_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:chatify/core/utils/status_expiry.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

class CreateStatusParams {
  const CreateStatusParams({
    required this.authorId,
    required this.mediaType,
    required this.ciphertextRef,
  });

  final String authorId;
  final String mediaType;
  final String ciphertextRef;
}

@injectable
class CreateStatusUseCase implements UseCase<Result<void>, CreateStatusParams> {
  CreateStatusUseCase(this._repository, this._uuid);

  final StatusRepository _repository;
  final Uuid _uuid;

  @override
  Future<Result<void>> call(CreateStatusParams params) {
    final now = DateTime.now().toUtc();
    final status = StatusItem(
      id: _uuid.v4(),
      authorId: params.authorId,
      mediaType: params.mediaType,
      ciphertextRef: params.ciphertextRef,
      createdAt: now,
      expiresAt: StatusExpiry.buildExpiry(now),
    );
    return _repository.createStatus(status);
  }
}
