import 'package:chatify/app/bootstrap.dart';
import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/auth_runtime.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/features/auth/presentation/bloc/auth_cubit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
  bool _refreshingRuntime = false;

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
        body: _buildScrollableBody(
          children: [
            const Text('Auth dependencies are not configured in this runtime.'),
            if (_allowDemoMode) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/home/chats'),
                child: const Text('Continue in demo mode'),
              ),
            ],
          ],
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
          final devOtpCode = state.devOtpCode?.trim();
          if (devOtpCode != null && devOtpCode.isNotEmpty) {
            _otpController
              ..text = devOtpCode
              ..selection = TextSelection.collapsed(offset: devOtpCode.length);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Test OTP auto-filled')),
            );
            context.read<AuthCubit>().consumeDevOtpCode();
            return;
          }
          if (state.status == AuthStatus.error && state.errorMessage != null) {
            AppLogger.breadcrumb(
              'auth.ui.error_shown',
              action: 'ui.snackbar',
              metadata: <String, Object?>{'message': state.errorMessage},
            );
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<AuthCubit>().clearError();
          }
        },
        builder: (context, state) {
          final authRuntime = AuthRuntimeController.current;
          final showOtpInput =
              state.status == AuthStatus.codeSent ||
              state.status == AuthStatus.verifyingCode ||
              state.canVerify;
          final sendingCode = state.status == AuthStatus.sendingCode;
          final verifyingCode = state.status == AuthStatus.verifyingCode;
          final fetchingDevCode = state.fetchingDevCode;
          final phoneOtpAvailable = !authRuntime.isUnavailable;
          final inputBusy = sendingCode || verifyingCode || fetchingDevCode;

          return Scaffold(
            appBar: AppBar(title: const Text('Sign in')),
            body: _buildScrollableBody(
              children: [
                _AuthRuntimeNotice(
                  runtime: authRuntime,
                  refreshing: _refreshingRuntime,
                  onRetry: _retryRuntimeConnection,
                ),
                if (!authRuntime.isUnavailable) const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  enabled: !inputBusy,
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
                  onPressed: !phoneOtpAvailable || inputBusy
                      ? null
                      : () => context.read<AuthCubit>().requestOtp(
                          _phoneController.text,
                        ),
                  child: Text(sendingCode ? 'Sending...' : 'Send OTP'),
                ),
                if (showOtpInput) ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    enabled: !verifyingCode && !fetchingDevCode,
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
                    child: Text(verifyingCode ? 'Verifying...' : 'Verify OTP'),
                  ),
                  if (kDebugMode && authRuntime.isEmulatorOnly) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: fetchingDevCode
                          ? null
                          : () => context
                                .read<AuthCubit>()
                                .fetchLatestDevOtpCode(),
                      child: Text(
                        fetchingDevCode
                            ? 'Fetching test code...'
                            : 'Auto-fill test OTP',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      authRuntime.statusMessage,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
                if (_allowDemoMode) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => context.go('/home/chats'),
                    child: const Text('Continue in demo mode'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScrollableBody({required List<Widget> children}) {
    final mediaQuery = MediaQuery.of(context);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + mediaQuery.viewInsets.bottom,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 40)
                    .clamp(0.0, double.infinity)
                    .toDouble(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
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

  Future<void> _retryRuntimeConnection() async {
    if (_refreshingRuntime) {
      return;
    }
    setState(() {
      _refreshingRuntime = true;
    });
    try {
      await refreshFirebaseRuntime();
    } finally {
      if (mounted) {
        setState(() {
          _refreshingRuntime = false;
        });
      }
    }
  }
}

class _AuthRuntimeNotice extends StatelessWidget {
  const _AuthRuntimeNotice({
    required this.runtime,
    required this.refreshing,
    required this.onRetry,
  });

  final AuthRuntimeState runtime;
  final bool refreshing;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (!runtime.isUnavailable) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              runtime.statusMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: refreshing ? null : onRetry,
                child: Text(
                  refreshing ? 'Retrying...' : 'Retry emulator connection',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
