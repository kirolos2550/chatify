import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/features/auth/domain/usecases/request_otp_use_case.dart';
import 'package:chatify/features/auth/domain/usecases/verify_otp_use_case.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

enum AuthStatus {
  idle,
  sendingCode,
  codeSent,
  verifyingCode,
  authenticated,
  error,
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.idle,
    this.errorMessage,
    this.verificationId,
    this.phoneNumber = '',
  });

  final AuthStatus status;
  final String? errorMessage;
  final String? verificationId;
  final String phoneNumber;

  bool get canVerify => verificationId != null && verificationId!.isNotEmpty;

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    String? verificationId,
    String? phoneNumber,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      verificationId: verificationId ?? this.verificationId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }
}

@injectable
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._requestOtpUseCase, this._verifyOtpUseCase)
    : super(const AuthState());

  final RequestOtpUseCase _requestOtpUseCase;
  final VerifyOtpUseCase _verifyOtpUseCase;

  Future<void> requestOtp(String phoneNumber) async {
    final normalized = _normalizePhone(phoneNumber);
    if (normalized == null) {
      AppLogger.warning(
        'Auth request OTP rejected due to invalid phone format',
        event: 'auth.request_otp.validation_failed',
        action: 'auth.request_otp',
        metadata: <String, Object?>{'phone': phoneNumber},
      );
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Enter a valid phone number in international format',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: AuthStatus.sendingCode,
        phoneNumber: normalized,
        clearError: true,
      ),
    );

    AppLogger.breadcrumb(
      'auth.request_otp.start',
      action: 'auth.request_otp',
      metadata: <String, Object?>{'phone': normalized},
    );

    final result = await _requestOtpUseCase(RequestOtpParams(normalized));
    if (result is Success<String>) {
      final verificationId = result.value;
      if (verificationId.isEmpty) {
        AppLogger.info(
          'Auth request OTP auto-completed and user authenticated',
          event: 'auth.request_otp.success',
          action: 'auth.request_otp',
          metadata: <String, Object?>{'autoVerified': true},
        );
        emit(
          state.copyWith(status: AuthStatus.authenticated, clearError: true),
        );
        return;
      }
      AppLogger.info(
        'Auth OTP code sent successfully',
        event: 'auth.request_otp.success',
        action: 'auth.request_otp',
        metadata: <String, Object?>{
          'autoVerified': false,
          'verificationId': verificationId,
        },
      );
      emit(
        state.copyWith(
          status: AuthStatus.codeSent,
          verificationId: verificationId,
          clearError: true,
        ),
      );
    } else {
      result.logIfFailure(
        event: 'auth.request_otp.failure',
        action: 'auth.request_otp',
        source: 'AuthCubit',
        operation: 'requestOtp',
        metadata: <String, Object?>{'phone': normalized},
      );
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: result.error?.message ?? 'Unknown error',
        ),
      );
    }
  }

  Future<void> verifyOtp(String code) async {
    final verificationId = state.verificationId;
    final otp = code.trim();
    if (verificationId == null || verificationId.isEmpty) {
      AppLogger.warning(
        'Auth verify OTP attempted without verification id',
        event: 'auth.verify_otp.validation_failed',
        action: 'auth.verify_otp',
      );
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Request OTP first',
        ),
      );
      return;
    }
    if (otp.length < 6) {
      AppLogger.warning(
        'Auth verify OTP rejected due to invalid code length',
        event: 'auth.verify_otp.validation_failed',
        action: 'auth.verify_otp',
        metadata: <String, Object?>{'otpLength': otp.length},
      );
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Enter the 6-digit OTP code',
        ),
      );
      return;
    }

    emit(state.copyWith(status: AuthStatus.verifyingCode, clearError: true));
    AppLogger.breadcrumb(
      'auth.verify_otp.start',
      action: 'auth.verify_otp',
      metadata: <String, Object?>{
        'verificationId': verificationId,
        'otpCode': otp,
      },
    );
    final result = await _verifyOtpUseCase(
      VerifyOtpParams(verificationId: verificationId, code: otp),
    );
    if (result is Success<void>) {
      AppLogger.info(
        'Auth verify OTP succeeded',
        event: 'auth.verify_otp.success',
        action: 'auth.verify_otp',
      );
      emit(state.copyWith(status: AuthStatus.authenticated, clearError: true));
    } else {
      result.logIfFailure(
        event: 'auth.verify_otp.failure',
        action: 'auth.verify_otp',
        source: 'AuthCubit',
        operation: 'verifyOtp',
        metadata: <String, Object?>{
          'verificationId': verificationId,
          'otpCode': otp,
        },
      );
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: result.error?.message ?? 'OTP verification failed',
        ),
      );
    }
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  String? _normalizePhone(String value) {
    var phone = value.trim();
    if (phone.isEmpty) {
      return null;
    }

    phone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    }
    if (!phone.startsWith('+')) {
      return null;
    }

    final digits = phone.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 15) {
      return null;
    }

    return '+$digits';
  }
}
