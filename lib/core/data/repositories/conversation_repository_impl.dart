import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/phone_normalizer.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/conversation.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/conversation_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

@LazySingleton(as: ConversationRepository)
class ConversationRepositoryImpl implements ConversationRepository {
  ConversationRepositoryImpl(this._firestore, this._auth, this._uuid);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid;

  @override
  Stream<List<Conversation>> watchConversations() {
    return _auth.authStateChanges().switchMap((user) {
      final uid = user?.uid;
      if (uid == null) {
        return Stream.value(const <Conversation>[]);
      }
      return _firestore
          .collection(FirebasePaths.conversations)
          .where('memberIds', arrayContains: uid)
          .snapshots()
          .asyncMap((snapshot) async {
            final conversations = await Future.wait(
              snapshot.docs.map((doc) => _fromDoc(doc, currentUserId: uid)),
            );
            conversations.sort(_compareByActivityDesc);
            return conversations;
          });
    });
  }

  @override
  Future<Result<String>> createDirectConversation({
    required String peerUserId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }
    final peerIdentifier = peerUserId.trim();
    if (peerIdentifier.isEmpty) {
      return const FailureResult(
        Failure('Peer user id or phone number is required'),
      );
    }
    try {
      final resolvedPeerUserId = await _resolvePeerUserId(peerIdentifier);
      if (resolvedPeerUserId == null) {
        return const FailureResult(
          Failure(
            'Peer user was not found. Ask them to sign in first, then use their user id or phone number.',
          ),
        );
      }
      if (resolvedPeerUserId == uid) {
        return const FailureResult(
          Failure('You cannot create a direct chat with yourself'),
        );
      }

      final existingId = await _findExistingDirectConversation(
        uid: uid,
        peerUserId: resolvedPeerUserId,
      );
      if (existingId != null) {
        return Success(existingId);
      }

      final id = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      final directKey = _buildDirectKey(uid, resolvedPeerUserId);
      final members = <String>[uid, resolvedPeerUserId];
      await _firestore.collection(FirebasePaths.conversations).doc(id).set({
        'type': 'direct',
        'title': null,
        'memberIds': members,
        'archivedByUserIds': const <String>[],
        'pinnedByUserIds': const <String>[],
        'unreadCountByUser': _initialUnreadCountByUser(members),
        'directKey': directKey,
        'createdAt': now,
        'updatedAt': now,
      });
      return Success(id);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<String>> createGroup({
    required String title,
    required List<String> memberUserIds,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return const FailureResult(Failure('Group title is required'));
    }
    try {
      final resolvedMembers = <String>{};
      for (final rawIdentifier in memberUserIds) {
        final identifier = rawIdentifier.trim();
        if (identifier.isEmpty) {
          continue;
        }
        final resolved = await _resolvePeerUserId(identifier);
        if (resolved == null || resolved == uid) {
          continue;
        }
        resolvedMembers.add(resolved);
      }

      if (resolvedMembers.isEmpty) {
        return const FailureResult(
          Failure(
            'No registered members could be resolved. Add at least one Chatify user by contact, phone, or user id.',
          ),
        );
      }

      final id = _uuid.v4();
      final allMembers = <String>{
        uid,
        ...resolvedMembers,
      }.toList(growable: false);
      final now = DateTime.now().millisecondsSinceEpoch;
      final ref = _firestore.collection(FirebasePaths.conversations).doc(id);
      await ref.set({
        'type': 'group',
        'title': trimmedTitle,
        'ownerId': uid,
        'memberIds': allMembers,
        'archivedByUserIds': const <String>[],
        'pinnedByUserIds': const <String>[],
        'unreadCountByUser': _initialUnreadCountByUser(allMembers),
        'createdAt': now,
        'updatedAt': now,
      });
      for (final member in allMembers) {
        await ref.collection(FirebasePaths.members).doc(member).set({
          'role': member == uid ? 'owner' : 'member',
          'joinedAt': now,
        });
      }
      return Success(id);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteConversation({
    required String conversationId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }

    try {
      final ref = _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId);
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        return const Success(null);
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final membersRaw = data['memberIds'];
      final members = membersRaw is List
          ? membersRaw.whereType<String>().toList()
          : const <String>[];
      if (!members.contains(uid)) {
        return const FailureResult(
          Failure('You do not have permission to delete this conversation'),
        );
      }

      await _deleteSubcollection(ref.collection(FirebasePaths.messages));
      await _deleteSubcollection(ref.collection(FirebasePaths.members));
      await _deleteSubcollection(ref.collection(FirebasePaths.receipts));
      await _deleteSubcollection(ref.collection(FirebasePaths.typing));
      await ref.delete();
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteConversationForMe({
    required String conversationId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }

    try {
      final ref = _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId);
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        return const Success(null);
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final membersRaw = data['memberIds'];
      final members = membersRaw is List
          ? membersRaw.whereType<String>().toList()
          : <String>[];
      if (!members.contains(uid)) {
        return const FailureResult(
          Failure('You do not have permission to delete this conversation'),
        );
      }

      final remaining = members.where((memberId) => memberId != uid).toList();
      if (remaining.isEmpty) {
        return deleteConversation(conversationId: conversationId);
      }

      await ref.set({
        'memberIds': remaining,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'unreadCountByUser.$uid': FieldValue.delete(),
      }, SetOptions(merge: true));

      final myMemberDoc = ref.collection(FirebasePaths.members).doc(uid);
      final myMemberSnapshot = await myMemberDoc.get();
      if (myMemberSnapshot.exists) {
        await myMemberDoc.delete();
      }
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> setConversationArchived({
    required String conversationId,
    required bool archived,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }

    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .set({
            'archivedByUserIds': archived
                ? FieldValue.arrayUnion([uid])
                : FieldValue.arrayRemove([uid]),
          }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }

    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .set({
            'pinnedByUserIds': pinned
                ? FieldValue.arrayUnion([uid])
                : FieldValue.arrayRemove([uid]),
          }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  Future<Conversation> _fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUserId,
  }) async {
    final data = doc.data() ?? {};
    final type = (data['type'] as String?) == 'group'
        ? ConversationType.group
        : ConversationType.direct;
    final archivedByUsers = _asStringSet(data['archivedByUserIds']);
    final pinnedByUsers = _asStringSet(data['pinnedByUserIds']);
    final memberIds = _asStringSet(data['memberIds']);
    var resolvedTitle = (data['title'] as String?)?.trim();
    var resolvedAvatarUrl = (data['avatarUrl'] as String?)?.trim();
    final unreadCount = await _resolveUnreadCount(
      conversationId: doc.id,
      data: data,
      currentUserId: currentUserId,
    );

    if (type == ConversationType.direct) {
      final peerUserId = _resolvePeerUserIdFromMembers(
        memberIds: memberIds,
        currentUserId: currentUserId,
      );
      if (peerUserId != null) {
        final peerProfile = await _loadUserProfile(peerUserId);
        if ((resolvedTitle == null || resolvedTitle.isEmpty) &&
            peerProfile?.displayName != null &&
            peerProfile!.displayName!.isNotEmpty) {
          resolvedTitle = peerProfile.displayName;
        }
        if ((resolvedAvatarUrl == null || resolvedAvatarUrl.isEmpty) &&
            peerProfile?.avatarUrl != null &&
            peerProfile!.avatarUrl!.isNotEmpty) {
          resolvedAvatarUrl = peerProfile.avatarUrl;
        }
      }
    }

    return Conversation(
      id: doc.id,
      type: type,
      title: resolvedTitle?.isEmpty ?? true ? null : resolvedTitle,
      avatarUrl: resolvedAvatarUrl?.isEmpty ?? true ? null : resolvedAvatarUrl,
      createdAt: _fromMillis(data['createdAt']),
      updatedAt: _fromMillis(data['updatedAt']),
      lastMessageId: data['lastMessageId'] as String?,
      unreadCount: unreadCount,
      isArchived: archivedByUsers.contains(currentUserId),
      isPinned: pinnedByUsers.contains(currentUserId),
    );
  }

  DateTime _fromMillis(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    return DateTime.now().toUtc();
  }

  int _compareByActivityDesc(Conversation left, Conversation right) {
    if (left.isPinned != right.isPinned) {
      return left.isPinned ? -1 : 1;
    }
    final leftActivity = left.updatedAt ?? left.createdAt;
    final rightActivity = right.updatedAt ?? right.createdAt;
    return rightActivity.compareTo(leftActivity);
  }

  Future<String?> _resolvePeerUserId(String peerIdentifier) async {
    final identifier = peerIdentifier.trim();
    if (identifier.isEmpty) {
      return null;
    }
    final usersRef = _firestore.collection(FirebasePaths.users);

    final byId = await usersRef.doc(identifier).get();
    if (byId.exists) {
      return byId.id;
    }

    final normalizedPhone = PhoneNormalizer.toE164(identifier);
    final phoneCandidates = <String>{
      identifier,
      if (normalizedPhone.isNotEmpty) normalizedPhone,
    };
    for (final phone in phoneCandidates) {
      final resolvedByPhone = await _resolveUserIdByField(
        usersRef: usersRef,
        field: 'phone',
        value: phone,
      );
      if (resolvedByPhone != null) {
        return resolvedByPhone;
      }
    }

    final digits = PhoneNormalizer.toDigits(identifier);
    if (digits.isNotEmpty) {
      final resolvedByDigits = await _resolveUserIdByField(
        usersRef: usersRef,
        field: 'phoneDigits',
        value: digits,
      );
      if (resolvedByDigits != null) {
        return resolvedByDigits;
      }
    }

    return null;
  }

  Future<String?> _resolveUserIdByField({
    required CollectionReference<Map<String, dynamic>> usersRef,
    required String field,
    required String value,
  }) async {
    if (value.trim().isEmpty) {
      return null;
    }
    final snapshot = await usersRef
        .where(field, isEqualTo: value)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return snapshot.docs.first.id;
  }

  Future<String?> _findExistingDirectConversation({
    required String uid,
    required String peerUserId,
  }) async {
    final directKey = _buildDirectKey(uid, peerUserId);
    final conversationsRef = _firestore.collection(FirebasePaths.conversations);

    final byDirectKey = await conversationsRef
        .where('directKey', isEqualTo: directKey)
        .limit(1)
        .get();
    if (byDirectKey.docs.isNotEmpty) {
      final doc = byDirectKey.docs.first;
      if ((doc.data()['type'] as String?) == 'direct') {
        return doc.id;
      }
    }

    final legacyMatches = await conversationsRef
        .where('memberIds', arrayContains: uid)
        .get();
    for (final doc in legacyMatches.docs) {
      final data = doc.data();
      if ((data['type'] as String?) != 'direct') {
        continue;
      }
      final membersRaw = data['memberIds'];
      if (membersRaw is! List) {
        continue;
      }
      final members = membersRaw.whereType<String>().toSet();
      if (members.length == 2 &&
          members.contains(uid) &&
          members.contains(peerUserId)) {
        await doc.reference.set({
          'directKey': directKey,
        }, SetOptions(merge: true));
        return doc.id;
      }
    }

    return null;
  }

  String _buildDirectKey(String left, String right) {
    final sorted = [left, right]..sort();
    return '${sorted.first}_${sorted.last}';
  }

  Set<String> _asStringSet(Object? value) {
    if (value is! List) {
      return const <String>{};
    }
    return value.whereType<String>().toSet();
  }

  Map<String, int> _asIntMap(Object? value) {
    if (value is! Map) {
      return const <String, int>{};
    }
    final map = <String, int>{};
    value.forEach((rawKey, rawValue) {
      if (rawKey is! String || rawKey.trim().isEmpty) {
        return;
      }
      final resolved = switch (rawValue) {
        int() => rawValue,
        num() => rawValue.toInt(),
        String() => int.tryParse(rawValue),
        _ => null,
      };
      if (resolved == null) {
        return;
      }
      map[rawKey] = resolved < 0 ? 0 : resolved;
    });
    return map;
  }

  Future<int> _resolveUnreadCount({
    required String conversationId,
    required Map<String, dynamic> data,
    required String currentUserId,
  }) async {
    final unreadMap = _asIntMap(data['unreadCountByUser']);
    final existingCount = unreadMap[currentUserId];
    if (existingCount != null) {
      return existingCount;
    }

    // Backfill for conversations created before unreadCountByUser was introduced.
    final fallbackCount = await _countUnreadMessages(
      conversationId: conversationId,
      currentUserId: currentUserId,
    );
    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .set({
            'unreadCountByUser.$currentUserId': fallbackCount,
          }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort cache only.
    }
    return fallbackCount;
  }

  Future<int> _countUnreadMessages({
    required String conversationId,
    required String currentUserId,
  }) async {
    const batchSize = 200;
    var unread = 0;
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    final messagesRef = _firestore
        .collection(FirebasePaths.conversations)
        .doc(conversationId)
        .collection(FirebasePaths.messages);

    while (true) {
      var query = messagesRef
          .orderBy('clientTimestamp', descending: true)
          .limit(batchSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        break;
      }

      for (final messageDoc in snapshot.docs) {
        final messageData = messageDoc.data();
        final senderId = (messageData['senderId'] as String?)?.trim() ?? '';
        if (senderId.isEmpty || senderId == currentUserId) {
          continue;
        }
        if (messageData['deletedForAllAt'] != null) {
          continue;
        }
        final deletedForUser = _asStringSet(messageData['deletedForUserIds']);
        if (deletedForUser.contains(currentUserId)) {
          continue;
        }
        final readByUsers = _asStringSet(messageData['readByUserIds']);
        if (readByUsers.contains(currentUserId)) {
          continue;
        }
        unread++;
      }

      cursor = snapshot.docs.last;
      if (snapshot.docs.length < batchSize) {
        break;
      }
    }

    return unread;
  }

  Map<String, int> _initialUnreadCountByUser(Iterable<String> memberIds) {
    final map = <String, int>{};
    for (final memberId in memberIds) {
      final id = memberId.trim();
      if (id.isEmpty) {
        continue;
      }
      map[id] = 0;
    }
    return map;
  }

  String? _resolvePeerUserIdFromMembers({
    required Set<String> memberIds,
    required String currentUserId,
  }) {
    for (final memberId in memberIds) {
      if (memberId != currentUserId && memberId.trim().isNotEmpty) {
        return memberId;
      }
    }
    return null;
  }

  Future<_UserProfileSummary?> _loadUserProfile(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(FirebasePaths.users)
          .doc(userId)
          .get();
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data() ?? const <String, dynamic>{};
      final displayName = (data['displayName'] as String?)?.trim();
      final phone = (data['phone'] as String?)?.trim();
      final avatarUrl = (data['avatarUrl'] as String?)?.trim();
      return _UserProfileSummary(
        displayName: (displayName != null && displayName.isNotEmpty)
            ? displayName
            : phone,
        avatarUrl: avatarUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    const batchSize = 200;

    while (true) {
      final snapshot = await collection.limit(batchSize).get();
      if (snapshot.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < batchSize) {
        break;
      }
    }
  }
}

class _UserProfileSummary {
  const _UserProfileSummary({this.displayName, this.avatarUrl});

  final String? displayName;
  final String? avatarUrl;
}
