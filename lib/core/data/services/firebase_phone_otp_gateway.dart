import 'dart:async';

import 'package:chatify/core/common/auth_runtime.dart';
import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/phone_normalizer.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/data/services/phone_otp_gateway.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: PhoneOtpGateway)
class FirebasePhoneOtpGateway implements PhoneOtpGateway {
  FirebasePhoneOtpGateway(this._auth, this._dio);

  static const _requestTimeout = Duration(seconds: 75);

  final FirebaseAuth _auth;
  final Dio _dio;

  @override
  Future<Result<PhoneOtpRequestResult>> requestCode({
    required String phoneNumber,
  }) async {
    final runtime = AuthRuntimeController.current;
    if (runtime.isUnavailable) {
      return FailureResult(
        Failure(
          runtime.statusMessage,
          code: 'auth_runtime_unavailable',
          source: 'FirebasePhoneOtpGateway',
          operation: 'requestCode',
        ),
      );
    }

    final completer = Completer<Result<PhoneOtpRequestResult>>();
    String? currentOtpSessionId;
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          try {
            await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete(
                const Success(PhoneOtpRequestResult.autoVerified()),
              );
            }
          } on FirebaseAuthException catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.complete(
                FailureResult(
                  _firebaseAuthFailure(
                    error,
                    operation: 'requestCode.verificationCompleted',
                    fallback: 'Auto OTP verification failed',
                    stackTrace: stackTrace,
                  ),
                ),
              );
            }
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.complete(
                FailureResult(
                  Failure.fromException(
                    error,
                    stackTrace: stackTrace,
                    message: 'Auto OTP verification failed',
                    source: 'FirebasePhoneOtpGateway',
                    operation: 'requestCode.verificationCompleted',
                  ),
                ),
              );
            }
          }
        },
        verificationFailed: (error) {
          if (!completer.isCompleted) {
            completer.complete(
              FailureResult(
                _firebaseAuthFailure(
                  error,
                  operation: 'requestCode.verificationFailed',
                  fallback: 'OTP request failed',
                ),
              ),
            );
          }
        },
        codeSent: (otpSessionId, _) {
          currentOtpSessionId = otpSessionId;
          if (!completer.isCompleted) {
            completer.complete(
              Success(PhoneOtpRequestResult.codeSent(otpSessionId)),
            );
          }
        },
        codeAutoRetrievalTimeout: (otpSessionId) {
          currentOtpSessionId ??= otpSessionId;
          final activeOtpSessionId = currentOtpSessionId;
          if (!completer.isCompleted && activeOtpSessionId != null) {
            completer.complete(
              Success(PhoneOtpRequestResult.codeSent(activeOtpSessionId)),
            );
          }
        },
      );

      return await completer.future.timeout(
        _requestTimeout,
        onTimeout: () => FailureResult(
          Failure(
            runtime.isEmulatorOnly
                ? 'OTP request timed out. Make sure Firebase Auth Emulator is running and reachable from this device.'
                : 'OTP request timed out. Check your network and try again.',
            code: 'otp_timeout',
            source: 'FirebasePhoneOtpGateway',
            operation: 'requestCode.timeout',
          ),
        ),
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      return FailureResult(
        _firebaseAuthFailure(
          error,
          operation: 'requestCode',
          fallback: 'OTP request failed',
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        Failure.fromException(
          error,
          stackTrace: stackTrace,
          source: 'FirebasePhoneOtpGateway',
          operation: 'requestCode',
        ),
      );
    }
  }

  @override
  Future<Result<void>> verifyCode({
    required String otpSessionId,
    required String otpCode,
  }) async {
    final runtime = AuthRuntimeController.current;
    if (runtime.isUnavailable) {
      return FailureResult(
        Failure(
          runtime.statusMessage,
          code: 'auth_runtime_unavailable',
          source: 'FirebasePhoneOtpGateway',
          operation: 'verifyCode',
        ),
      );
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: otpSessionId,
        smsCode: otpCode,
      );
      await _auth.signInWithCredential(credential);
      return const Success(null);
    } on FirebaseAuthException catch (error, stackTrace) {
      return FailureResult(
        _firebaseAuthFailure(
          error,
          operation: 'verifyCode',
          fallback: 'OTP verification failed',
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        Failure.fromException(
          error,
          stackTrace: stackTrace,
          source: 'FirebasePhoneOtpGateway',
          operation: 'verifyCode',
        ),
      );
    }
  }

  @override
  Future<Result<String?>> fetchLatestDevCode({
    required String phoneNumber,
    String? otpSessionId,
  }) async {
    final runtime = AuthRuntimeController.current;
    if (!runtime.isEmulatorOnly) {
      return FailureResult(
        Failure(
          'Test OTP helper is only available while using Firebase Auth Emulator.',
          code: 'dev_otp_unavailable',
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    }

    final host = runtime.emulatorHost?.trim();
    if (host == null || host.isEmpty) {
      return const FailureResult(
        Failure(
          'Firebase Auth Emulator host is missing.',
          code: 'missing_emulator_host',
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    }

    if (Firebase.apps.isEmpty) {
      return const FailureResult(
        Failure(
          'Firebase is not initialized for this runtime.',
          code: 'firebase_unavailable',
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    }

    final projectId = Firebase.app().options.projectId.trim();
    if (projectId.isEmpty) {
      return const FailureResult(
        Failure(
          'Firebase project id is missing for Auth Emulator requests.',
          code: 'missing_project_id',
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    }

    final normalizedPhone = PhoneNormalizer.toE164(phoneNumber);
    if (normalizedPhone.isEmpty) {
      return const FailureResult(
        Failure(
          'Enter a valid phone number in international format.',
          code: 'invalid_phone_number',
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    }

    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: 9099,
        path: '/emulator/v1/projects/$projectId/verificationCodes',
      );
      final response = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (statusCode) =>
              statusCode != null && statusCode >= 200 && statusCode < 500,
        ),
      );

      if (response.statusCode != 200) {
        return FailureResult(
          Failure(
            'Could not fetch test OTP from Firebase Auth Emulator. Check emulator connectivity and try again.',
            code: 'emulator_rest_error',
            source: 'FirebasePhoneOtpGateway',
            operation: 'fetchLatestDevCode',
            metadata: <String, Object?>{'statusCode': response.statusCode},
          ),
        );
      }

      final responseData = response.data;
      if (responseData is! Map<String, dynamic>) {
        return const FailureResult(
          Failure(
            'Unexpected response from Firebase Auth Emulator.',
            code: 'invalid_emulator_response',
            source: 'FirebasePhoneOtpGateway',
            operation: 'fetchLatestDevCode',
          ),
        );
      }

      final items = responseData['verificationCodes'];
      if (items is! List) {
        return const Success(null);
      }

      for (final entry in items.reversed) {
        if (entry is! Map) {
          continue;
        }
        final rawPhone = entry['phoneNumber']?.toString().trim() ?? '';
        if (PhoneNormalizer.toE164(rawPhone) != normalizedPhone) {
          continue;
        }

        final rawOtpSessionId =
            entry['sessionInfo']?.toString().trim() ??
            entry['verificationId']?.toString().trim() ??
            '';
        if (otpSessionId != null &&
            otpSessionId.isNotEmpty &&
            rawOtpSessionId != otpSessionId) {
          continue;
        }

        final code =
            entry['code']?.toString().trim() ??
            entry['smsCode']?.toString().trim() ??
            '';
        if (code.isNotEmpty) {
          return Success(code);
        }
      }

      return const Success(null);
    } on DioException catch (error, stackTrace) {
      return FailureResult(
        Failure.network(
          message:
              'Could not reach Firebase Auth Emulator to fetch the latest test OTP.',
          cause: error,
          stackTrace: stackTrace,
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        Failure.fromException(
          error,
          stackTrace: stackTrace,
          source: 'FirebasePhoneOtpGateway',
          operation: 'fetchLatestDevCode',
        ),
      );
    }
  }

  Failure _firebaseAuthFailure(
    FirebaseAuthException error, {
    required String operation,
    required String fallback,
    StackTrace? stackTrace,
  }) {
    return Failure(
      _friendlyAuthMessage(
        code: error.code,
        message: error.message,
        fallback: fallback,
      ),
      code: error.code,
      source: 'FirebasePhoneOtpGateway',
      operation: operation,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  String _friendlyAuthMessage({
    required String fallback,
    String? code,
    String? message,
  }) {
    final rawMessage = (message ?? '').toUpperCase();
    if (rawMessage.contains('CONFIGURATION_NOT_FOUND')) {
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
