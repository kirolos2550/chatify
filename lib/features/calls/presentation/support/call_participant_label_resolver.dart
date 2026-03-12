import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CallParticipantLabelResolver {
  CallParticipantLabelResolver({
    required ContactsRepository? contactsRepository,
    required FirebaseFirestore? firestore,
  }) : _contactsRepository = contactsRepository,
       _firestore = firestore;

  final ContactsRepository? _contactsRepository;
  final FirebaseFirestore? _firestore;

  final Map<String, String> _contactDisplayNameByUserId = <String, String>{};
  final Map<String, String> _phoneNumberByUserId = <String, String>{};
  final Map<String, String> _profileDisplayNameByUserId = <String, String>{};
  final Set<String> _pendingRemoteUserIds = <String>{};
  final Set<String> _loadedRemoteUserIds = <String>{};

  bool _contactsLoadStarted = false;

  Future<bool> preloadContacts() async {
    if (_contactsLoadStarted) {
      return false;
    }
    _contactsLoadStarted = true;

    final repository = _contactsRepository;
    if (repository == null) {
      return false;
    }

    final result = await repository.fetchContactCandidates();
    final candidates = result.data ?? const [];
    var didChange = false;

    for (final candidate in candidates) {
      if (!candidate.isRegistered) {
        continue;
      }
      final userId = candidate.registeredUserId?.trim();
      if (userId == null || userId.isEmpty) {
        continue;
      }

      final localPhone = _firstNonEmpty(
        candidate.normalizedPhoneE164,
        candidate.rawPhone,
      );
      if (localPhone != null &&
          (_phoneNumberByUserId[userId]?.trim().isEmpty ?? true)) {
        _phoneNumberByUserId[userId] = localPhone;
        didChange = true;
      }

      final displayName = candidate.displayName.trim();
      if (!_isUsableContactName(displayName)) {
        continue;
      }
      if (_contactDisplayNameByUserId[userId] == displayName) {
        continue;
      }
      _contactDisplayNameByUserId[userId] = displayName;
      didChange = true;
    }

    return didChange;
  }

  Future<bool> ensureRemoteProfilesLoaded(Iterable<String> userIds) async {
    final requestedIds = userIds
        .map((userId) => userId.trim())
        .where((userId) => userId.isNotEmpty)
        .toSet();
    if (requestedIds.isEmpty) {
      return false;
    }

    final missingIds = requestedIds
        .where(
          (userId) =>
              !_loadedRemoteUserIds.contains(userId) &&
              !_pendingRemoteUserIds.contains(userId),
        )
        .toList(growable: false);
    if (missingIds.isEmpty) {
      return false;
    }

    final firestore = _firestore;
    if (firestore == null) {
      _loadedRemoteUserIds.addAll(missingIds);
      return false;
    }

    _pendingRemoteUserIds.addAll(missingIds);
    var didChange = false;

    try {
      for (final chunk in _chunks(missingIds, 10)) {
        final snapshot = await firestore
            .collection(FirebasePaths.users)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final phone = _readString(data['phone']);
          if (phone != null &&
              (_phoneNumberByUserId[doc.id]?.trim().isEmpty ?? true)) {
            _phoneNumberByUserId[doc.id] = phone;
            didChange = true;
          }

          final displayName = _readString(data['displayName']);
          if (displayName != null &&
              _profileDisplayNameByUserId[doc.id] != displayName) {
            _profileDisplayNameByUserId[doc.id] = displayName;
            didChange = true;
          }
        }
      }

      _loadedRemoteUserIds.addAll(missingIds);
      return didChange;
    } catch (_) {
      _loadedRemoteUserIds.addAll(missingIds);
      return didChange;
    } finally {
      _pendingRemoteUserIds.removeAll(missingIds);
    }
  }

  String resolveLabel(String userId, {String? currentUserId}) {
    final normalizedUserId = userId.trim();
    final normalizedCurrentUserId = currentUserId?.trim();

    if (normalizedUserId.isEmpty) {
      return 'Unknown';
    }
    if (normalizedCurrentUserId != null &&
        normalizedCurrentUserId.isNotEmpty &&
        normalizedUserId == normalizedCurrentUserId) {
      return 'You';
    }

    final contactName = _contactDisplayNameByUserId[normalizedUserId];
    if (_isUsableContactName(contactName)) {
      return contactName!.trim();
    }

    final phoneNumber = _phoneNumberByUserId[normalizedUserId]?.trim();
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      return phoneNumber;
    }

    final profileDisplayName = _profileDisplayNameByUserId[normalizedUserId]
        ?.trim();
    if (profileDisplayName != null && profileDisplayName.isNotEmpty) {
      return profileDisplayName;
    }

    if (normalizedUserId.length <= 16) {
      return normalizedUserId;
    }
    return '${normalizedUserId.substring(0, 16)}...';
  }

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _firstNonEmpty(String first, String second) {
    final normalizedFirst = first.trim();
    if (normalizedFirst.isNotEmpty) {
      return normalizedFirst;
    }

    final normalizedSecond = second.trim();
    if (normalizedSecond.isNotEmpty) {
      return normalizedSecond;
    }

    return null;
  }

  bool _isUsableContactName(String? value) {
    if (value == null) {
      return false;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.toLowerCase() != 'unknown';
  }

  List<List<String>> _chunks(List<String> source, int size) {
    final output = <List<String>>[];
    for (var index = 0; index < source.length; index += size) {
      output.add(
        source.sublist(
          index,
          index + size > source.length ? source.length : index + size,
        ),
      );
    }
    return output;
  }
}
