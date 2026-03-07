import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/device.dart';
import 'package:chatify/core/domain/repositories/device_link_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

@LazySingleton(as: DeviceLinkRepository)
class DeviceLinkRepositoryImpl implements DeviceLinkRepository {
  DeviceLinkRepositoryImpl(this._firestore, this._auth, this._uuid);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid;

  @override
  Future<Result<void>> linkDeviceConfirm({required String linkCode}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FailureResult(Failure('No active user'));
    }
    try {
      await _firestore
          .collection(FirebasePaths.users)
          .doc(uid)
          .collection(FirebasePaths.devices)
          .doc(linkCode)
          .set({
            'publicIdentityKey': 'pending-key',
            'lastSeenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<String>> linkDeviceStart() async {
    try {
      return Success(_uuid.v4());
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Stream<List<Device>> watchLinkedDevices() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection(FirebasePaths.users)
        .doc(uid)
        .collection(FirebasePaths.devices)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return Device(
              deviceId: doc.id,
              userId: uid,
              publicIdentityKey: data['publicIdentityKey'] as String? ?? '',
              lastSeenAt:
                  _toDateTime(data['lastSeenAt']) ?? DateTime.now().toUtc(),
            );
          }).toList();
        });
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }
}
