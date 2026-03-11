import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/phone_normalizer.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/entities/contact_candidate.dart';
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
  Future<Result<List<ContactCandidate>>> fetchContactCandidates() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        return const FailureResult(Failure('Contacts permission denied'));
      }

      final localContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );

      final localEntries = <_LocalContactEntry>[];
      final e164Phones = <String>{};
      final digitPhones = <String>{};
      final seenPhoneKeys = <String>{};

      for (final contact in localContacts) {
        final displayName = _resolveDisplayName(contact);
        for (final phone in contact.phones) {
          final normalization = PhoneNormalizer.normalize(phone.number);
          if (!normalization.hasAnyValue) {
            continue;
          }

          final dedupeKey = normalization.normalizedE164.isNotEmpty
              ? 'e:${normalization.normalizedE164}'
              : 'd:${normalization.digits}';
          if (!seenPhoneKeys.add(dedupeKey)) {
            continue;
          }

          localEntries.add(
            _LocalContactEntry(
              displayName: displayName,
              rawPhone: normalization.raw,
              normalizedPhoneE164: normalization.normalizedE164,
              phoneDigits: normalization.digits,
            ),
          );

          if (normalization.normalizedE164.isNotEmpty) {
            e164Phones.add(normalization.normalizedE164);
          }
          if (normalization.digits.isNotEmpty) {
            digitPhones.add(normalization.digits);
          }
        }
      }

      if (localEntries.isEmpty) {
        return const Success(<ContactCandidate>[]);
      }

      final usersByE164 = await _loadUserIdsByField(
        field: 'phone',
        values: e164Phones,
      );
      final usersByDigits = await _loadUserIdsByField(
        field: 'phoneDigits',
        values: digitPhones,
      );

      final candidates =
          localEntries
              .map((entry) {
                final byE164 = entry.normalizedPhoneE164.isNotEmpty
                    ? usersByE164[entry.normalizedPhoneE164]
                    : null;
                final byDigits = entry.phoneDigits.isNotEmpty
                    ? usersByDigits[entry.phoneDigits]
                    : null;
                final userId = byE164 ?? byDigits;
                return ContactCandidate(
                  displayName: entry.displayName,
                  rawPhone: entry.rawPhone,
                  normalizedPhoneE164: entry.normalizedPhoneE164,
                  phoneDigits: entry.phoneDigits,
                  registeredUserId: userId,
                  isRegistered: userId != null && userId.isNotEmpty,
                );
              })
              .toList(growable: false)
            ..sort((left, right) {
              if (left.isRegistered != right.isRegistered) {
                return left.isRegistered ? -1 : 1;
              }
              return left.displayName.toLowerCase().compareTo(
                right.displayName.toLowerCase(),
              );
            });

      return Success(candidates);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<List<AppUser>>> syncContacts() async {
    final candidatesResult = await fetchContactCandidates();
    if (candidatesResult is FailureResult<List<ContactCandidate>>) {
      return FailureResult(candidatesResult.failure);
    }

    final result = candidatesResult.data ?? const <ContactCandidate>[];
    final usersById = <String, AppUser>{};
    for (final candidate in result) {
      final userId = candidate.registeredUserId;
      if (candidate.isRegistered != true || userId == null || userId.isEmpty) {
        continue;
      }
      usersById[userId] = AppUser(
        id: userId,
        phone: candidate.normalizedPhoneE164.isNotEmpty
            ? candidate.normalizedPhoneE164
            : candidate.rawPhone,
        displayName: candidate.displayName,
        createdAt: DateTime.now().toUtc(),
      );
    }

    return Success(usersById.values.toList(growable: false));
  }

  String _resolveDisplayName(Contact contact) {
    final direct = contact.displayName.trim();
    if (direct.isNotEmpty) {
      return direct;
    }
    final fallback = contact.name.first.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }
    return 'Unknown';
  }

  Future<Map<String, String>> _loadUserIdsByField({
    required String field,
    required Set<String> values,
  }) async {
    if (values.isEmpty) {
      return const <String, String>{};
    }

    final output = <String, String>{};
    final chunks = _chunks(values.toList(growable: false), 10);
    for (final chunk in chunks) {
      final snapshot = await _firestore
          .collection(FirebasePaths.users)
          .where(field, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final key = (data[field] as String?)?.trim();
        if (key == null || key.isEmpty) {
          continue;
        }
        output[key] = doc.id;
      }
    }
    return output;
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

class _LocalContactEntry {
  const _LocalContactEntry({
    required this.displayName,
    required this.rawPhone,
    required this.normalizedPhoneE164,
    required this.phoneDigits,
  });

  final String displayName;
  final String rawPhone;
  final String normalizedPhoneE164;
  final String phoneDigits;
}
