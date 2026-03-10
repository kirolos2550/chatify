import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class UserPrivacySettings {
  const UserPrivacySettings({
    this.readReceiptsEnabled = true,
    this.lastSeenVisible = true,
    this.typingVisibilityEnabled = true,
  });

  final bool readReceiptsEnabled;
  final bool lastSeenVisible;
  final bool typingVisibilityEnabled;

  UserPrivacySettings copyWith({
    bool? readReceiptsEnabled,
    bool? lastSeenVisible,
    bool? typingVisibilityEnabled,
  }) {
    return UserPrivacySettings(
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      lastSeenVisible: lastSeenVisible ?? this.lastSeenVisible,
      typingVisibilityEnabled:
          typingVisibilityEnabled ?? this.typingVisibilityEnabled,
    );
  }
}

class UserPrivacyService {
  const UserPrivacyService._();

  static UserPrivacySettings defaults() => const UserPrivacySettings();

  static Future<UserPrivacySettings> loadMySettings() async {
    final uid = _currentUid();
    if (uid == null) {
      return defaults();
    }
    return loadForUid(uid);
  }

  static Future<UserPrivacySettings> loadForUid(String uid) async {
    if (Firebase.apps.isEmpty) {
      return defaults();
    }
    try {
      final snapshot = await _settingsDoc(uid).get();
      final data = snapshot.data() ?? const <String, Object?>{};
      return UserPrivacySettings(
        readReceiptsEnabled: _asBool(
          data['readReceiptsEnabled'],
          fallback: true,
        ),
        lastSeenVisible: _asBool(data['lastSeenVisible'], fallback: true),
        typingVisibilityEnabled: _asBool(
          data['typingVisibilityEnabled'],
          fallback: true,
        ),
      );
    } on FirebaseException catch (error, stackTrace) {
      AppLogger.error(
        'Failed to load user privacy settings from Firebase',
        error,
        stackTrace,
        event: 'privacy.load.failure',
        source: 'UserPrivacyService',
        operation: 'loadForUid',
        action: 'settings.privacy.load',
        metadata: <String, Object?>{'uid': uid},
      );
      // If rules block this document, keep app behavior stable using defaults.
      return defaults();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Unexpected failure while loading privacy settings',
        error,
        stackTrace,
        event: 'privacy.load.exception',
        source: 'UserPrivacyService',
        operation: 'loadForUid',
        action: 'settings.privacy.load',
        metadata: <String, Object?>{'uid': uid},
      );
      return defaults();
    }
  }

  static Future<void> updateMySettings({
    bool? readReceiptsEnabled,
    bool? lastSeenVisible,
    bool? typingVisibilityEnabled,
  }) async {
    final uid = _currentUid();
    if (uid == null || Firebase.apps.isEmpty) {
      return;
    }
    final payload = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (readReceiptsEnabled != null) {
      payload['readReceiptsEnabled'] = readReceiptsEnabled;
    }
    if (lastSeenVisible != null) {
      payload['lastSeenVisible'] = lastSeenVisible;
    }
    if (typingVisibilityEnabled != null) {
      payload['typingVisibilityEnabled'] = typingVisibilityEnabled;
    }
    try {
      await _settingsDoc(uid).set(payload, SetOptions(merge: true));

      if (lastSeenVisible != null) {
        await FirebaseFirestore.instance
            .collection(FirebasePaths.presence)
            .doc(uid)
            .set({
              'showLastSeen': lastSeenVisible,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } on FirebaseException catch (error, stackTrace) {
      AppLogger.error(
        'Failed to update user privacy settings in Firebase',
        error,
        stackTrace,
        event: 'privacy.update.failure',
        source: 'UserPrivacyService',
        operation: 'updateMySettings',
        action: 'settings.privacy.update',
        metadata: <String, Object?>{
          'uid': uid,
          'readReceiptsEnabled': readReceiptsEnabled,
          'lastSeenVisible': lastSeenVisible,
          'typingVisibilityEnabled': typingVisibilityEnabled,
        },
      );
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Unexpected failure while updating privacy settings',
        error,
        stackTrace,
        event: 'privacy.update.exception',
        source: 'UserPrivacyService',
        operation: 'updateMySettings',
        action: 'settings.privacy.update',
        metadata: <String, Object?>{
          'uid': uid,
          'readReceiptsEnabled': readReceiptsEnabled,
          'lastSeenVisible': lastSeenVisible,
          'typingVisibilityEnabled': typingVisibilityEnabled,
        },
      );
      rethrow;
    }
  }

  static String? _currentUid() {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static DocumentReference<Map<String, dynamic>> _settingsDoc(String uid) {
    return FirebaseFirestore.instance
        .collection(FirebasePaths.users)
        .doc(uid)
        .collection(FirebasePaths.privacy)
        .doc(FirebasePaths.settings);
  }

  static bool _asBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    return fallback;
  }
}
