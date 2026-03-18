enum AuthRuntimeMode { emulatorOnly, live, unavailable }

class AuthRuntimeState {
  const AuthRuntimeState({
    required this.mode,
    this.emulatorHost,
    this.unavailableReason,
  });

  const AuthRuntimeState.emulatorOnly({required String emulatorHost})
    : this(mode: AuthRuntimeMode.emulatorOnly, emulatorHost: emulatorHost);

  const AuthRuntimeState.live() : this(mode: AuthRuntimeMode.live);

  const AuthRuntimeState.unavailable({required String reason})
    : this(mode: AuthRuntimeMode.unavailable, unavailableReason: reason);

  final AuthRuntimeMode mode;
  final String? emulatorHost;
  final String? unavailableReason;

  bool get isEmulatorOnly => mode == AuthRuntimeMode.emulatorOnly;
  bool get isLive => mode == AuthRuntimeMode.live;
  bool get isUnavailable => mode == AuthRuntimeMode.unavailable;

  String get statusMessage {
    switch (mode) {
      case AuthRuntimeMode.emulatorOnly:
        final host = emulatorHost?.trim();
        return host == null || host.isEmpty
            ? 'Phone OTP is running against Firebase Auth Emulator.'
            : 'Phone OTP is running against Firebase Auth Emulator on $host:9099.';
      case AuthRuntimeMode.live:
        return 'Live phone OTP is enabled for this build.';
      case AuthRuntimeMode.unavailable:
        return unavailableReason?.trim().isNotEmpty == true
            ? unavailableReason!.trim()
            : 'Phone OTP is unavailable in this runtime.';
    }
  }
}

abstract final class AuthRuntimeController {
  static AuthRuntimeState _current = const AuthRuntimeState.unavailable(
    reason: 'Phone OTP is unavailable in this runtime.',
  );

  static AuthRuntimeState get current => _current;

  static void setCurrent(AuthRuntimeState state) {
    _current = state;
  }
}
