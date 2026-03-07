import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/status_item.dart';
import 'package:chatify/core/domain/repositories/status_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: StatusRepository)
class StatusRepositoryImpl implements StatusRepository {
  StatusRepositoryImpl(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<void>> createStatus(StatusItem item) async {
    try {
      await _firestore
          .collection(FirebasePaths.status)
          .doc(item.authorId)
          .collection(FirebasePaths.items)
          .doc(item.id)
          .set({
            'authorId': item.authorId,
            'mediaType': item.mediaType,
            'ciphertextRef': item.ciphertextRef,
            'createdAt': item.createdAt.millisecondsSinceEpoch,
            'expiresAt': item.expiresAt.millisecondsSinceEpoch,
          });
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteExpiredStatuses() async {
    try {
      // Scheduled cleanup is performed by cloud functions.
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Stream<List<StatusItem>> watchStatusFeed() {
    return _firestore.collectionGroup(FirebasePaths.items).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            final authorId = data['authorId'] as String?;
            if (authorId == null || authorId.isEmpty) {
              return null;
            }
            final createdAt = _fromInstant(data['createdAt']);
            final expiresAt = _fromInstant(data['expiresAt']);
            if (createdAt == null || expiresAt == null) {
              return null;
            }
            return StatusItem(
              id: doc.id,
              authorId: authorId,
              mediaType: data['mediaType'] as String? ?? 'text',
              ciphertextRef: data['ciphertextRef'] as String? ?? '',
              createdAt: createdAt,
              expiresAt: expiresAt,
            );
          })
          .whereType<StatusItem>()
          .where((item) => !item.isExpired)
          .toList();
    });
  }

  DateTime? _fromInstant(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
      }
    }
    return null;
  }
}
