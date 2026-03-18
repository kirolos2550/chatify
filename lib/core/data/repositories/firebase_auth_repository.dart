import 'dart:async';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/phone_normalizer.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/core/data/services/phone_otp_gateway.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: AuthRepository)
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
    this._auth,
    this._firestore,
    this._secureStorage,
    this._phoneOtpGateway,
  );

  static const _pinKey = 'two_step_pin';
  static const _otpSessionIdKey = 'otp_session_id';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _secureStorage;
  final PhoneOtpGateway _phoneOtpGateway;

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.authStateChanges().map((firebaseUser) {
      if (firebaseUser == null) {
        return null;
      }
      return AppUser(
        id: firebaseUser.uid,
        phone: firebaseUser.phoneNumber ?? '',
        displayName: firebaseUser.displayName ?? 'User',
        avatarUrl: firebaseUser.photoURL,
        createdAt:
            firebaseUser.metadata.creationTime?.toUtc() ??
            DateTime.now().toUtc(),
      );
    });
  }

  @override
  Future<Result<String>> requestOtp({required String phoneNumber}) async {
    try {
      final result = await _phoneOtpGateway.requestCode(
        phoneNumber: phoneNumber,
      );
      if (result is FailureResult<PhoneOtpRequestResult>) {
        return FailureResult(
          _buildAndLogFailureFromFailure(
            result.failure,
            operation: 'requestOtp',
          ),
        );
      }

      final requestResult = result.data!;
      if (requestResult.autoVerified) {
        final user = _auth.currentUser;
        if (user != null) {
          await _upsertUserDocument(user);
        }
        await _secureStorage.delete(key: _otpSessionIdKey);
        return const Success('');
      }

      final otpSessionId = requestResult.otpSessionId.trim();
      await _secureStorage.write(key: _otpSessionIdKey, value: otpSessionId);
      return Success(otpSessionId);
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(e, stackTrace: stackTrace, operation: 'requestOtp'),
      );
    }
  }

  @override
  Future<Result<void>> verifyOtp({
    required String otpSessionId,
    required String otpCode,
  }) async {
    try {
      final result = await _phoneOtpGateway.verifyCode(
        otpSessionId: otpSessionId,
        otpCode: otpCode,
      );
      if (result is FailureResult<void>) {
        return FailureResult(
          _buildAndLogFailureFromFailure(
            result.failure,
            operation: 'verifyOtp',
          ),
        );
      }
      final user = _auth.currentUser;
      if (user != null) {
        await _upsertUserDocument(user);
      }
      await _secureStorage.delete(key: _otpSessionIdKey);
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(e, stackTrace: stackTrace, operation: 'verifyOtp'),
      );
    }
  }

  @override
  Future<Result<String?>> fetchLatestDevOtpCode({
    required String phoneNumber,
    String? otpSessionId,
  }) async {
    try {
      final result = await _phoneOtpGateway.fetchLatestDevCode(
        phoneNumber: phoneNumber,
        otpSessionId: otpSessionId,
      );
      if (result is FailureResult<String?>) {
        return FailureResult(
          _buildAndLogFailureFromFailure(
            result.failure,
            operation: 'fetchLatestDevOtpCode',
          ),
        );
      }
      return result;
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(
          e,
          stackTrace: stackTrace,
          operation: 'fetchLatestDevOtpCode',
        ),
      );
    }
  }

  @override
  Future<Result<void>> setTwoStepPin({required String pin}) async {
    try {
      await _secureStorage.write(key: _pinKey, value: pin);
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(
          e,
          stackTrace: stackTrace,
          operation: 'setTwoStepPin',
        ),
      );
    }
  }

  @override
  Future<Result<void>> updateProfile({
    required String displayName,
    String? about,
    String? avatarUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const FailureResult(Failure('No active user'));
    }

    try {
      await user.updateDisplayName(displayName);
      if (avatarUrl != null) {
        await user.updatePhotoURL(avatarUrl);
      }
      await _upsertUserDocument(
        user,
        displayName: displayName,
        about: about,
        avatarUrl: avatarUrl,
      );
      await user.reload();
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(
          e,
          stackTrace: stackTrace,
          operation: 'updateProfile',
        ),
      );
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      return const Success(null);
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(e, stackTrace: stackTrace, operation: 'signOut'),
      );
    }
  }

  Future<String?> consumeOtpSessionId() async {
    final id = await _secureStorage.read(key: _otpSessionIdKey);
    await _secureStorage.delete(key: _otpSessionIdKey);
    return id;
  }

  Future<void> _upsertUserDocument(
    User user, {
    String? displayName,
    String? about,
    String? avatarUrl,
  }) async {
    final userRef = _firestore.collection(FirebasePaths.users).doc(user.uid);
    final existing = await userRef.get();
    final normalizedDisplayName = _resolveDisplayName(displayName, user);
    final effectiveAvatarUrl = avatarUrl ?? user.photoURL;
    final phoneNumber = user.phoneNumber ?? '';

    final payload = <String, Object?>{
      'id': user.uid,
      'phone': phoneNumber,
      'phoneDigits': PhoneNormalizer.toDigits(phoneNumber),
      'displayName': normalizedDisplayName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (effectiveAvatarUrl != null && effectiveAvatarUrl.isNotEmpty) {
      payload['avatarUrl'] = effectiveAvatarUrl;
    }
    if (about != null) {
      payload['about'] = about;
    }

    if (!existing.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    await userRef.set(payload, SetOptions(merge: true));
  }

  String _resolveDisplayName(String? displayName, User user) {
    final candidate = (displayName ?? user.displayName ?? '').trim();
    if (candidate.isEmpty) {
      return 'User';
    }
    return candidate;
  }

  Failure _buildAndLogFailure(
    Object error, {
    StackTrace? stackTrace,
    required String operation,
    String? message,
    String? code,
  }) {
    final failure = Failure.fromException(
      error,
      stackTrace: stackTrace,
      message: message,
      code: code,
      source: 'FirebaseAuthRepository',
      operation: operation,
    );
    AppLogger.error(
      failure.message,
      failure.cause ?? error,
      failure.stackTrace ?? stackTrace,
      event: 'auth.repository.failure',
      source: failure.source,
      operation: failure.operation,
      action: 'auth.repository',
      metadata: <String, Object?>{'failureCode': failure.code},
    );
    return failure;
  }

  Failure _buildAndLogFailureFromFailure(
    Failure failure, {
    required String operation,
  }) {
    final normalized = failure.copyWith(
      source: failure.source ?? 'FirebaseAuthRepository',
      operation: failure.operation ?? operation,
    );
    AppLogger.error(
      normalized.message,
      normalized.cause ?? failure,
      normalized.stackTrace,
      event: 'auth.repository.failure',
      source: normalized.source,
      operation: normalized.operation,
      action: 'auth.repository',
      metadata: <String, Object?>{'failureCode': normalized.code},
    );
    return normalized;
  }
}
