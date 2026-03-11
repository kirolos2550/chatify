import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/entities/contact_candidate.dart';

abstract interface class ContactsRepository {
  Future<Result<void>> requestContactsPermission();

  Future<Result<List<ContactCandidate>>> fetchContactCandidates();

  Future<Result<List<AppUser>>> syncContacts();
}
