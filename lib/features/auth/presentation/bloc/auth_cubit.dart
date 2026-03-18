import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/features/auth/domain/usecases/fetch_latest_dev_otp_code_use_case.dart';
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
    this.otpSessionId,
    this.phoneNumber = '',
    this.fetchingDevCode = false,
    this.devOtpCode,
  });

  final AuthStatus status;
  final String? errorMessage;
  final String? otpSessionId;
  final String phoneNumber;
  final bool fetchingDevCode;
  final String? devOtpCode;

  bool get canVerify => otpSessionId != null && otpSessionId!.isNotEmpty;

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    String? otpSessionId,
    String? phoneNumber,
    bool? fetchingDevCode,
    String? devOtpCode,
    bool clearError = false,
    bool clearDevOtpCode = false,
    bool clearOtpSessionId = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      otpSessionId: clearOtpSessionId
          ? null
          : otpSessionId ?? this.otpSessionId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      fetchingDevCode: fetchingDevCode ?? this.fetchingDevCode,
      devOtpCode: clearDevOtpCode ? null : devOtpCode ?? this.devOtpCode,
    );
  }
}

@injectable
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(
    this._requestOtpUseCase,
    this._verifyOtpUseCase,
    this._fetchLatestDevOtpCodeUseCase,
  ) : super(const AuthState());

  final RequestOtpUseCase _requestOtpUseCase;
  final VerifyOtpUseCase _verifyOtpUseCase;
  final FetchLatestDevOtpCodeUseCase _fetchLatestDevOtpCodeUseCase;

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
          clearOtpSessionId: true,
          clearDevOtpCode: true,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: AuthStatus.sendingCode,
        phoneNumber: normalized,
        clearError: true,
        clearDevOtpCode: true,
        clearOtpSessionId: true,
      ),
    );

    AppLogger.breadcrumb(
      'auth.request_otp.start',
      action: 'auth.request_otp',
      metadata: <String, Object?>{'phone': normalized},
    );

    final result = await _requestOtpUseCase(RequestOtpParams(normalized));
    if (result is Success<String>) {
      final otpSessionId = result.value;
      if (otpSessionId.isEmpty) {
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
          'otpSessionId': otpSessionId,
        },
      );
      emit(
        state.copyWith(
          status: AuthStatus.codeSent,
          otpSessionId: otpSessionId,
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
    final otpSessionId = state.otpSessionId;
    final otp = code.trim();
    if (otpSessionId == null || otpSessionId.isEmpty) {
      AppLogger.warning(
        'Auth verify OTP attempted without OTP session id',
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
      metadata: <String, Object?>{'otpSessionId': otpSessionId, 'otpCode': otp},
    );
    final result = await _verifyOtpUseCase(
      VerifyOtpParams(otpSessionId: otpSessionId, code: otp),
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
          'otpSessionId': otpSessionId,
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

  Future<void> fetchLatestDevOtpCode() async {
    final phoneNumber = state.phoneNumber.trim();
    if (phoneNumber.isEmpty) {
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Request OTP first',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        fetchingDevCode: true,
        clearError: true,
        clearDevOtpCode: true,
      ),
    );
    final result = await _fetchLatestDevOtpCodeUseCase(
      FetchLatestDevOtpCodeParams(
        phoneNumber: phoneNumber,
        otpSessionId: state.otpSessionId,
      ),
    );
    if (result is Success<String?>) {
      final code = result.value?.trim();
      if (code == null || code.isEmpty) {
        emit(
          state.copyWith(
            fetchingDevCode: false,
            status: AuthStatus.error,
            errorMessage:
                'No test OTP was found yet. Request a code first, then try again.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          fetchingDevCode: false,
          devOtpCode: code,
          clearError: true,
        ),
      );
      return;
    }

    result.logIfFailure(
      event: 'auth.fetch_dev_otp.failure',
      action: 'auth.fetch_dev_otp',
      source: 'AuthCubit',
      operation: 'fetchLatestDevOtpCode',
      metadata: <String, Object?>{
        'phone': phoneNumber,
        'otpSessionId': state.otpSessionId,
      },
    );
    emit(
      state.copyWith(
        fetchingDevCode: false,
        status: AuthStatus.error,
        errorMessage: result.error?.message ?? 'Could not fetch test OTP',
      ),
    );
  }

  void consumeDevOtpCode() {
    emit(state.copyWith(clearDevOtpCode: true));
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
