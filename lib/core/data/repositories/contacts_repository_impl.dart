import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ContactsRepository)
class ContactsRepositoryImpl implements ContactsRepository {
  ContactsRepositoryImpl(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<void>> requestContactsPermission() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      return const FailureResult(Failure('Contacts permission denied'));
    }
    return const Success(null);
  }

  @override
  Future<Result<List<AppUser>>> syncContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        return const FailureResult(Failure('Contacts permission denied'));
      }

      final localContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );
      final phones = <String>{};
      for (final c in localContacts) {
        for (final p in c.phones) {
          final normalized = _normalizePhone(p.number);
          if (normalized.isNotEmpty) {
            phones.add(normalized);
          }
        }
      }

      if (phones.isEmpty) {
        return const Success(<AppUser>[]);
      }

      final results = <AppUser>[];
      final chunks = _chunks(phones.toList(), 10);
      for (final chunk in chunks) {
        final snapshot = await _firestore
            .collection(FirebasePaths.users)
            .where('phone', whereIn: chunk)
            .get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          results.add(
            AppUser(
              id: doc.id,
              phone: data['phone'] as String? ?? '',
              displayName: data['displayName'] as String? ?? 'User',
              avatarUrl: data['avatarUrl'] as String?,
              about: data['about'] as String?,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }
      }
      return Success(results);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    return digits;
  }

  List<List<T>> _chunks<T>(List<T> source, int size) {
    final output = <List<T>>[];
    for (var i = 0; i < source.length; i += size) {
      output.add(
        source.sublist(i, i + size > source.length ? source.length : i + size),
      );
    }
    return output;
  }
}
