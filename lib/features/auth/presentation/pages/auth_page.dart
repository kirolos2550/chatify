import 'package:chatify/app/di/injection.dart';
import 'package:chatify/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

const bool _useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: true,
);
const bool _allowDemoMode = bool.fromEnvironment(
  'ALLOW_DEMO_MODE',
  defaultValue: true,
);

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  AuthCubit? _authCubit;
  bool _sessionRedirectTriggered = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _authCubit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authCubit = _resolveAuthCubit();
    if (authCubit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sign in')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Auth dependencies are not configured in this runtime.',
              ),
              if (_allowDemoMode) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/home/chats'),
                  child: const Text('Continue in demo mode'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (!_sessionRedirectTriggered &&
        FirebaseAuth.instance.currentUser != null) {
      _sessionRedirectTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/home/chats');
        }
      });
    }

    return BlocProvider.value(
      value: authCubit,
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state.status == AuthStatus.authenticated) {
            context.go('/home/chats');
            return;
          }
          if (state.status == AuthStatus.error &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<AuthCubit>().clearError();
          }
        },
        builder: (context, state) {
          final showOtpInput =
              state.status == AuthStatus.codeSent ||
              state.status == AuthStatus.verifyingCode ||
              state.canVerify;
          final sendingCode = state.status == AuthStatus.sendingCode;
          final verifyingCode = state.status == AuthStatus.verifyingCode;

          return Scaffold(
            appBar: AppBar(title: const Text('Sign in')),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    enabled: !sendingCode && !verifyingCode,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+2010XXXXXXXX',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use international format (E.164), for example +2010...',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: sendingCode || verifyingCode
                        ? null
                        : () => context.read<AuthCubit>().requestOtp(
                            _phoneController.text,
                          ),
                    child: Text(sendingCode ? 'Sending...' : 'Send OTP'),
                  ),
                  if (kDebugMode && _useFirebaseEmulators) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'You are running with Firebase emulators. '
                      'To verify real phone numbers, run with '
                      '--dart-define=USE_FIREBASE_EMULATORS=false.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  if (showOtpInput) ...[
                    const SizedBox(height: 24),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      enabled: !verifyingCode,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'OTP code',
                        hintText: '123456',
                        counterText: '',
                      ),
                      onSubmitted: (_) => context.read<AuthCubit>().verifyOtp(
                        _otpController.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: verifyingCode
                          ? null
                          : () => context.read<AuthCubit>().verifyOtp(
                              _otpController.text,
                            ),
                      child: Text(
                        verifyingCode ? 'Verifying...' : 'Verify OTP',
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_allowDemoMode)
                    TextButton(
                      onPressed: () => context.go('/home/chats'),
                      child: const Text('Continue in demo mode'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  AuthCubit? _resolveAuthCubit() {
    if (_authCubit != null) {
      return _authCubit;
    }
    if (!getIt.isRegistered<AuthCubit>() || Firebase.apps.isEmpty) {
      return null;
    }
    try {
      _authCubit = getIt<AuthCubit>();
      return _authCubit;
    } catch (_) {
      return null;
    }
  }
}
