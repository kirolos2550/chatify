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
    final result = await _requestOtpUseCase(RequestOtpParams(normalized));
    if (result is Success<String>) {
      final verificationId = result.value;
      if (verificationId.isEmpty) {
        emit(
          state.copyWith(status: AuthStatus.authenticated, clearError: true),
        );
        return;
      }
      emit(
        state.copyWith(
          status: AuthStatus.codeSent,
          verificationId: verificationId,
          clearError: true,
        ),
      );
    } else {
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
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Request OTP first',
        ),
      );
      return;
    }
    if (otp.length < 6) {
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Enter the 6-digit OTP code',
        ),
      );
      return;
    }

    emit(state.copyWith(status: AuthStatus.verifyingCode, clearError: true));
    final result = await _verifyOtpUseCase(
      VerifyOtpParams(verificationId: verificationId, code: otp),
    );
    if (result is Success<void>) {
      emit(state.copyWith(status: AuthStatus.authenticated, clearError: true));
    } else {
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
