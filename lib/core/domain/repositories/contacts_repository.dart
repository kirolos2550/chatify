import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';

abstract interface class ContactsRepository {
  Future<Result<void>> requestContactsPermission();

  Future<Result<List<AppUser>>> syncContacts();
}
