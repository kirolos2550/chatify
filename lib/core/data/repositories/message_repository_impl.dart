import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/data/local/app_database.dart';
import 'package:chatify/core/domain/entities/message.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/message_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: MessageRepository)
class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl(this._firestore, this._db);

  final FirebaseFirestore _firestore;
  final AppDatabase _db;

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return _firestore
        .collection(FirebasePaths.conversations)
        .doc(conversationId)
        .collection(FirebasePaths.messages)
        .orderBy('clientTimestamp')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _fromDoc(conversationId, doc))
              .where(
                (message) =>
                    currentUid == null ||
                    !message.deletedForUserIds.contains(currentUid),
              )
              .toList(),
        );
  }

  @override
  Future<Result<void>> sendMessage({
    required String conversationId,
    required Message message,
  }) async {
    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .collection(FirebasePaths.messages)
          .doc(message.id)
          .set({
            'senderId': message.senderId,
            'type': message.type.name,
            'ciphertext': message.ciphertext,
            'clientTimestamp': message.clientTimestamp.millisecondsSinceEpoch,
            'deviceId': message.deviceId,
            'e2eeVersion': message.e2eeVersion,
            'replyToMessageId': message.replyToMessageId,
            'deletedForAllAt': null,
            'editedAt': null,
            'deletedForUserIds': const <String>[],
            'deliveredToUserIds': const <String>[],
            'readByUserIds': const <String>[],
          });

      await _db
          .into(_db.messagesTable)
          .insertOnConflictUpdate(
            MessagesTableCompanion.insert(
              id: message.id,
              conversationId: conversationId,
              senderId: message.senderId,
              type: message.type.name,
              ciphertext: Uint8List.fromList(message.ciphertext.codeUnits),
              clientMsgTs: message.clientTimestamp.millisecondsSinceEpoch,
              localStatus: LocalMessageStatus.sent.name,
              deviceId: message.deviceId,
              e2eeVersion: Value(message.e2eeVersion),
              replyToMessageId: Value(message.replyToMessageId),
            ),
          );
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> editMessage({
    required String conversationId,
    required String messageId,
    required String editCiphertext,
  }) async {
    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .collection(FirebasePaths.messages)
          .doc(messageId)
          .set({
            'ciphertext': editCiphertext,
            'editedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteMessageForEveryone({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .collection(FirebasePaths.messages)
          .doc(messageId)
          .set({
            'deletedForAllAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteMessageForMe({
    required String conversationId,
    required String messageId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }
    try {
      await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .collection(FirebasePaths.messages)
          .doc(messageId)
          .set({
            'deletedForUserIds': FieldValue.arrayUnion([uid]),
          }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .collection(FirebasePaths.messages)
          .orderBy('clientTimestamp', descending: true)
          .limit(60)
          .get();

      if (snapshot.docs.isEmpty) {
        return const Success(null);
      }

      final batch = _firestore.batch();
      var updates = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final senderId = data['senderId'] as String? ?? '';
        if (senderId == userId) {
          continue;
        }
        if (data['deletedForAllAt'] != null) {
          continue;
        }

        final deliveredTo = _asStringList(data['deliveredToUserIds']).toSet();
        final readBy = _asStringList(data['readByUserIds']).toSet();
        final didChange = deliveredTo.add(userId) | readBy.add(userId);
        if (!didChange) {
          continue;
        }

        updates++;
        batch.set(doc.reference, {
          'deliveredToUserIds': deliveredTo.toList(growable: false),
          'readByUserIds': readBy.toList(growable: false),
        }, SetOptions(merge: true));
      }

      if (updates > 0) {
        await batch.commit();
      }
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> clearConversationMessages({
    required String conversationId,
  }) async {
    try {
      final messagesRef = _firestore
          .collection(FirebasePaths.conversations)
          .doc(conversationId)
          .collection(FirebasePaths.messages);
      const batchSize = 200;

      while (true) {
        final snapshot = await messagesRef.limit(batchSize).get();
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

      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  Message _fromDoc(
    String conversationId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final messageType = MessageType.values.firstWhere(
      (value) => value.name == (data['type'] as String?),
      orElse: () => MessageType.text,
    );
    return Message(
      id: doc.id,
      conversationId: conversationId,
      senderId: data['senderId'] as String? ?? '',
      type: messageType,
      ciphertext: data['ciphertext'] as String? ?? '',
      clientTimestamp:
          _fromInstant(data['clientTimestamp']) ?? DateTime.now().toUtc(),
      localStatus: LocalMessageStatus.sent,
      deviceId: data['deviceId'] as String? ?? '',
      replyToMessageId: data['replyToMessageId'] as String?,
      e2eeVersion: data['e2eeVersion'] as String? ?? 'signal-v1',
      editedAt: _fromInstant(data['editedAt']),
      deletedForAllAt: _fromInstant(data['deletedForAllAt']),
      deletedForUserIds: _asStringList(data['deletedForUserIds']),
      deliveredToUserIds: _asStringList(data['deliveredToUserIds']),
      readByUserIds: _asStringList(data['readByUserIds']),
    );
  }

  List<String> _asStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList(growable: false);
  }

  DateTime? _fromInstant(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    return null;
  }
}
