import 'dart:async';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/phone_normalizer.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: AuthRepository)
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._firestore, this._secureStorage);

  static const _pinKey = 'two_step_pin';
  static const _verificationIdKey = 'otp_verification_id';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _secureStorage;

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
    final completer = Completer<Result<String>>();
    String? currentVerificationId;
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          try {
            await _auth.signInWithCredential(credential);
            final user = _auth.currentUser;
            if (user != null) {
              await _upsertUserDocument(user);
            }
            if (!completer.isCompleted) {
              completer.complete(Success(currentVerificationId ?? ''));
            }
          } on FirebaseAuthException catch (e) {
            if (!completer.isCompleted) {
              final failure = _buildAndLogAuthFailure(
                message: e.message ?? 'Auto OTP verification failed',
                code: e.code,
                operation: 'requestOtp.verificationCompleted',
                cause: e,
              );
              completer.complete(FailureResult(failure));
            }
          } catch (e, stackTrace) {
            if (!completer.isCompleted) {
              completer.complete(
                FailureResult(
                  _buildAndLogFailure(
                    e,
                    stackTrace: stackTrace,
                    operation: 'requestOtp.verificationCompleted',
                    message: 'Auto OTP verification failed',
                  ),
                ),
              );
            }
          }
        },
        verificationFailed: (e) {
          if (!completer.isCompleted) {
            final failure = _buildAndLogAuthFailure(
              message: _friendlyAuthMessage(
                code: e.code,
                message: e.message,
                fallback: 'OTP request failed',
              ),
              code: e.code,
              operation: 'requestOtp.verificationFailed',
              cause: e,
            );
            completer.complete(FailureResult(failure));
          }
        },
        codeSent: (verificationId, _) async {
          currentVerificationId = verificationId;
          await _secureStorage.write(
            key: _verificationIdKey,
            value: verificationId,
          );
          if (!completer.isCompleted) {
            completer.complete(Success(verificationId));
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          currentVerificationId ??= verificationId;
          if (!completer.isCompleted && currentVerificationId != null) {
            completer.complete(Success(currentVerificationId!));
          }
        },
      );
      final result = await completer.future.timeout(
        const Duration(seconds: 75),
        onTimeout: () => FailureResult(
          _buildAndLogFailure(
            TimeoutException('requestOtp timeout after 75 seconds'),
            operation: 'requestOtp.timeout',
            message:
                'OTP request timed out. Check your network, and if you are in dev mode make sure Firebase Auth emulator is running or disable USE_FIREBASE_EMULATORS.',
            code: 'otp_timeout',
          ),
        ),
      );
      return result;
    } on FirebaseAuthException catch (e) {
      return FailureResult(
        _buildAndLogAuthFailure(
          message: _friendlyAuthMessage(
            code: e.code,
            message: e.message,
            fallback: 'OTP request failed',
          ),
          code: e.code,
          operation: 'requestOtp',
          cause: e,
        ),
      );
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(e, stackTrace: stackTrace, operation: 'requestOtp'),
      );
    }
  }

  @override
  Future<Result<void>> verifyOtp({
    required String verificationId,
    required String otpCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otpCode,
      );
      await _auth.signInWithCredential(credential);
      final user = _auth.currentUser;
      if (user != null) {
        await _upsertUserDocument(user);
      }
      return const Success(null);
    } on FirebaseAuthException catch (e) {
      return FailureResult(
        _buildAndLogAuthFailure(
          message: _friendlyAuthMessage(
            code: e.code,
            message: e.message,
            fallback: 'OTP verification failed',
          ),
          code: e.code,
          operation: 'verifyOtp',
          cause: e,
        ),
      );
    } catch (e, stackTrace) {
      return FailureResult(
        _buildAndLogFailure(e, stackTrace: stackTrace, operation: 'verifyOtp'),
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

  Future<String?> consumeVerificationId() async {
    final id = await _secureStorage.read(key: _verificationIdKey);
    await _secureStorage.delete(key: _verificationIdKey);
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

  Failure _buildAndLogAuthFailure({
    required String message,
    required String? code,
    required String operation,
    required Object cause,
    StackTrace? stackTrace,
  }) {
    final failure = Failure(
      message,
      code: code,
      source: 'FirebaseAuthRepository',
      operation: operation,
      cause: cause,
      stackTrace: stackTrace,
    );
    AppLogger.error(
      failure.message,
      failure.cause ?? cause,
      failure.stackTrace,
      event: 'auth.repository.failure',
      source: failure.source,
      operation: failure.operation,
      action: 'auth.repository',
      metadata: <String, Object?>{'failureCode': failure.code},
    );
    return failure;
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

  String _friendlyAuthMessage({
    required String fallback,
    String? code,
    String? message,
  }) {
    final raw = (message ?? '').toUpperCase();
    if (raw.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase Authentication is not configured for this project yet. Open Firebase Console > Authentication > Get started, enable Phone, then try again.';
    }
    switch (code) {
      case 'app-not-authorized':
        return 'This app is not authorized in Firebase. Check Android package name and SHA fingerprints.';
      case 'invalid-phone-number':
        return 'Invalid phone number format.';
      case 'operation-not-allowed':
        return 'Phone sign-in is disabled in Firebase Authentication.';
      case 'quota-exceeded':
        return 'SMS quota exceeded for this project. Try again later.';
      case 'too-many-requests':
        return 'Too many OTP requests. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'captcha-check-failed':
        return 'App verification failed. Retry and make sure Google Play services are available.';
      case 'session-expired':
        return 'OTP session expired. Request a new code.';
      case 'invalid-verification-code':
        return 'The OTP code is invalid.';
      case 'invalid-verification-id':
        return 'The OTP session is invalid. Request a new code.';
      default:
        break;
    }
    return message ?? fallback;
  }
}
