import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/core/domain/usecases/use_case.dart';
import 'package:injectable/injectable.dart';

@injectable
class SyncContactsUseCase implements UseCase<Result<List<AppUser>>, NoParams> {
  SyncContactsUseCase(this._repository);

  final ContactsRepository _repository;

  @override
  Future<Result<List<AppUser>>> call(NoParams params) {
    return _repository.syncContacts();
  }
}
