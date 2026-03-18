import 'dart:async';

import 'package:chatify/app/app.dart';
import 'package:chatify/app/di/injection.dart';
import 'package:chatify/app/emulator_port_probe.dart';
import 'package:chatify/app/flavor.dart';
import 'package:chatify/core/common/auth_runtime.dart';
import 'package:chatify/app/localization/app_locale_controller.dart';
import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/app/theme/app_theme_controller.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/crypto/crypto_engine.dart';
import 'package:chatify/core/crypto/signal_crypto_engine.dart';
import 'package:chatify/core/data/services/device_identity_service.dart';
import 'package:chatify/core/domain/repositories/message_repository.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:chatify/core/notifications/chat_local_notifications.dart';
import 'package:chatify/core/notifications/message_notification_orchestrator.dart';
import 'package:chatify/features/chats/data/repositories/message_repository_fallback.dart';
import 'package:chatify/features/chats/data/services/scheduled_message_service.dart';
import 'package:chatify/features/chats/domain/usecases/send_text_message_use_case.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:chatify/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:uuid/uuid.dart';

const bool _useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: true,
);
const String _firebaseEmulatorHostOverride = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
);
const bool _enableCrashlyticsInDebug = bool.fromEnvironment(
  'CRASHLYTICS_IN_DEBUG',
  defaultValue: false,
);
const bool _enableLivePhoneAuth = bool.fromEnvironment(
  'ENABLE_LIVE_PHONE_AUTH',
  defaultValue: false,
);
const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://uhovvyhmfqogjrayqigl.supabase.co',
);
const String _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_qW4G6ek9jzbPtw1Fe3e8TQ_9IhYLBwy',
);
const String _supabaseStorageBucket = String.fromEnvironment(
  'SUPABASE_STORAGE_BUCKET',
  defaultValue: 'chat-media',
);

bool _emulatorsConfigured = false;
bool _supabaseInitialized = false;
AppFlavor? _bootstrappedFlavor;
AppLifecycleListener? _lifecycleListener;
Timer? _uiHangWatchdog;
DateTime? _uiHangLastTick;
const Duration _uiHangProbeInterval = Duration(milliseconds: 700);
const Duration _uiHangThreshold = Duration(seconds: 4);
StreamSubscription<User?>? _incomingCallAuthSubscription;
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
_incomingCallSubscription;
StreamSubscription<User?>? _scheduledMessageAuthSubscription;
final Set<String> _notifiedIncomingCallIds = <String>{};

Future<void> bootstrap(AppFlavor flavor) async {
  await runZonedGuarded(
    () async {
      _bootstrappedFlavor = flavor;
      WidgetsFlutterBinding.ensureInitialized();
      await AppLogger.initDebugSession(
        flavor: flavor.nameValue,
        buildMode: kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      );

      final previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        previousFlutterErrorHandler?.call(details);
        AppLogger.error(
          'FlutterError',
          details.exception,
          details.stack,
          event: 'flutter.framework.error',
        );
        unawaited(_recordFlutterFatalError(details));
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        AppLogger.error(
          'PlatformError',
          error,
          stackTrace,
          event: 'flutter.platform.error',
        );
        unawaited(_recordError(error, stackTrace, fatal: true));
        return true;
      };

      await _initFirebase();
      await _initSupabase();
      await _configureCrashlytics(flavor);
      await _configureFirebaseRuntime(flavor);
      await configureDependencies(flavor);
      await _initLocalNotificationRouting();
      await AppLocaleController.instance.load();
      await AppThemeController.instance.load();
      await _initScheduledMessages();
      runApp(ChatifyApp(flavor: flavor));
      MessageNotificationOrchestrator.instance.start();
      _startUiHangWatchdog();
      _startIncomingCallAlerts();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.enableRouteTracing();
      });

      _lifecycleListener ??= AppLifecycleListener(
        onStateChange: (state) {
          AppLogger.breadcrumb(
            'app.lifecycle.$state',
            action: 'lifecycle.state_change',
          );
          switch (state) {
            case AppLifecycleState.inactive:
            case AppLifecycleState.paused:
            case AppLifecycleState.hidden:
            case AppLifecycleState.detached:
              unawaited(AppLogger.flush());
              break;
            case AppLifecycleState.resumed:
              unawaited(ScheduledMessageService.instance.processDueMessages());
              break;
          }
        },
        onDetach: () {
          _uiHangWatchdog?.cancel();
          _uiHangWatchdog = null;
          _incomingCallSubscription?.cancel();
          _incomingCallSubscription = null;
          _incomingCallAuthSubscription?.cancel();
          _incomingCallAuthSubscription = null;
          _scheduledMessageAuthSubscription?.cancel();
          _scheduledMessageAuthSubscription = null;
          _notifiedIncomingCallIds.clear();
          unawaited(MessageNotificationOrchestrator.instance.stop());
          unawaited(AppLogger.flushAndClose());
        },
      );
    },
    (error, stackTrace) {
      AppLogger.error(
        'ZoneError',
        error,
        stackTrace,
        event: 'flutter.zone.error',
      );
      unawaited(_recordError(error, stackTrace, fatal: true));
    },
  );
}

Future<AuthRuntimeState> refreshFirebaseRuntime() async {
  final flavor = _bootstrappedFlavor;
  if (flavor == null) {
    const unavailable = AuthRuntimeState.unavailable(
      reason:
          'App flavor is not initialized yet. Restart the app and try again.',
    );
    AuthRuntimeController.setCurrent(unavailable);
    return unavailable;
  }
  await _configureFirebaseRuntime(flavor);
  return AuthRuntimeController.current;
}

void _startUiHangWatchdog() {
  _uiHangWatchdog?.cancel();
  _uiHangLastTick = DateTime.now().toUtc();
  _uiHangWatchdog = Timer.periodic(_uiHangProbeInterval, (_) {
    final now = DateTime.now().toUtc();
    final previous = _uiHangLastTick;
    if (previous != null) {
      final gap = now.difference(previous);
      if (gap > _uiHangThreshold) {
        AppLogger.warning(
          'Potential UI stall detected',
          event: 'diagnostics.ui_stall.detected',
          action: 'diagnostics.ui_stall',
          metadata: <String, Object?>{
            'gapMs': gap.inMilliseconds,
            'thresholdMs': _uiHangThreshold.inMilliseconds,
          },
        );
      }
    }
    _uiHangLastTick = now;
  });
}

void _startIncomingCallAlerts() {
  if (Firebase.apps.isEmpty || _incomingCallAuthSubscription != null) {
    return;
  }

  _incomingCallAuthSubscription = FirebaseAuth.instance
      .authStateChanges()
      .listen((user) {
        _incomingCallSubscription?.cancel();
        _incomingCallSubscription = null;
        _notifiedIncomingCallIds.clear();
        if (user == null) {
          return;
        }

        _incomingCallSubscription = FirebaseFirestore.instance
            .collection(FirebasePaths.calls)
            .where('participantIds', arrayContains: user.uid)
            .snapshots()
            .listen(
              (snapshot) {
                final activeIncomingRingingIds = <String>{};
                for (final doc in snapshot.docs) {
                  final data = doc.data();
                  final state = (data['state'] as String?)?.trim() ?? '';
                  final initiatorId =
                      (data['initiatorId'] as String?)?.trim() ?? '';
                  if (state != 'ringing' ||
                      initiatorId.isEmpty ||
                      initiatorId == user.uid) {
                    continue;
                  }
                  activeIncomingRingingIds.add(doc.id);
                  if (_notifiedIncomingCallIds.contains(doc.id)) {
                    continue;
                  }
                  _notifiedIncomingCallIds.add(doc.id);
                  final callType = (data['type'] as String?) == 'video'
                      ? 'video'
                      : 'voice';
                  final callerLabel = initiatorId;
                  unawaited(
                    _showIncomingCallNotification(
                      callId: doc.id,
                      callerLabel: callerLabel,
                      callType: callType,
                    ),
                  );
                }
                _notifiedIncomingCallIds.retainAll(activeIncomingRingingIds);
              },
              onError: (Object error, StackTrace stackTrace) {
                AppLogger.error(
                  'Incoming call listener failed',
                  error,
                  stackTrace,
                  event: 'calls.incoming.listener_failure',
                  action: 'calls.incoming.listen',
                );
              },
            );
      });
}

Future<void> _initScheduledMessages() async {
  await ScheduledMessageService.instance.initialize(
    dispatcher: _dispatchScheduledMessage,
    currentUserIdProvider: _scheduledMessageCurrentUserId,
  );

  _scheduledMessageAuthSubscription?.cancel();
  if (Firebase.apps.isEmpty) {
    return;
  }

  _scheduledMessageAuthSubscription = FirebaseAuth.instance
      .authStateChanges()
      .listen((_) {
        unawaited(ScheduledMessageService.instance.processDueMessages());
      });
}

String? _scheduledMessageCurrentUserId() {
  if (Firebase.apps.isEmpty) {
    return 'local-debug-user';
  }
  return FirebaseAuth.instance.currentUser?.uid;
}

Future<bool> _dispatchScheduledMessage(ScheduledMessageTask task) async {
  final currentUserId = _scheduledMessageCurrentUserId();
  if (currentUserId == null || currentUserId.trim() != task.senderId.trim()) {
    return false;
  }

  try {
    final useCase = _resolveScheduledSendTextMessageUseCase();
    final result = await useCase(
      SendTextMessageParams(
        conversationId: task.conversationId,
        senderId: task.senderId,
        plaintext: task.plaintext,
        peerDeviceId: 'peer-${task.conversationId}',
        replyToMessageId: task.replyToMessageId,
      ),
    );
    return result.error == null;
  } catch (error, stackTrace) {
    AppLogger.error(
      'Scheduled message dispatch failed',
      error,
      stackTrace,
      event: 'chat.schedule.dispatch_failure',
      action: 'chat.schedule',
      metadata: <String, Object?>{
        'conversationId': task.conversationId,
        'scheduledFor': task.scheduledFor.toIso8601String(),
      },
    );
    return false;
  }
}

SendTextMessageUseCase _resolveScheduledSendTextMessageUseCase() {
  if (Firebase.apps.isNotEmpty) {
    try {
      return getIt<SendTextMessageUseCase>();
    } catch (_) {
      // Fall back to a lightweight local sender below.
    }
  }

  return SendTextMessageUseCase(
    _resolveScheduledMessageRepository(),
    _resolveScheduledCryptoEngine(),
    getIt<DeviceIdentityService>(),
    getIt<Uuid>(),
  );
}

MessageRepository _resolveScheduledMessageRepository() {
  if (Firebase.apps.isEmpty) {
    return fallbackMessageRepository;
  }
  try {
    return getIt<MessageRepository>();
  } catch (_) {
    return fallbackMessageRepository;
  }
}

CryptoEngine _resolveScheduledCryptoEngine() {
  if (getIt.isRegistered<CryptoEngine>()) {
    try {
      return getIt<CryptoEngine>();
    } catch (_) {
      // Fall back to the lightweight implementation below.
    }
  }
  return SignalCryptoEngine();
}

Future<void> _showIncomingCallNotification({
  required String callId,
  required String callerLabel,
  required String callType,
}) async {
  if (!getIt.isRegistered<ChatLocalNotifications>()) {
    return;
  }
  try {
    final notifications = getIt<ChatLocalNotifications>();
    await notifications.initialize(
      onNotificationTap: _handleLocalNotificationTap,
    );
    await notifications.showIncomingCallAlert(
      id: callId.hashCode & 0x7fffffff,
      callerLabel: callerLabel,
      callId: callId,
      callType: callType,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Incoming call notification failed',
      error,
      stackTrace,
      event: 'calls.incoming.notification_failure',
      action: 'calls.incoming.notify',
      metadata: <String, Object?>{'callId': callId},
    );
  }
}

Future<void> _initLocalNotificationRouting() async {
  if (!getIt.isRegistered<ChatLocalNotifications>()) {
    return;
  }
  try {
    final notifications = getIt<ChatLocalNotifications>();
    await notifications.initialize(
      onNotificationTap: _handleLocalNotificationTap,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Local notification routing init failed',
      error,
      stackTrace,
      event: 'notifications.local.init_failure',
      action: 'notifications.local.init',
    );
  }
}

Future<void> _handleLocalNotificationTap(String payload) async {
  if (!payload.startsWith('call:')) {
    return;
  }
  final callId = payload.substring('call:'.length).trim();
  if (callId.isEmpty) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final targetPath = '/call/${Uri.encodeComponent(callId)}';
    final currentPath = AppRouter.router.state.uri.toString();
    if (currentPath == targetPath) {
      return;
    }
    AppRouter.router.push(targetPath);
  });
}

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    await Firebase.initializeApp();
  } catch (error, stackTrace) {
    // During local setup, Firebase native config can be absent.
    if (kDebugMode) {
      AppLogger.error(
        'Firebase initialization skipped',
        error,
        stackTrace,
        event: 'firebase.init.skipped',
      );
    }
  }
}

Future<void> _initSupabase() async {
  if (_supabaseInitialized) {
    return;
  }
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    if (kDebugMode) {
      AppLogger.info(
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY to enable media uploads via Supabase.',
        event: 'supabase.init.skipped',
      );
    }
    return;
  }

  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      debug: kDebugMode,
    );
    _supabaseInitialized = true;
    AppLogger.info(
      'Supabase initialized for media storage.',
      event: 'supabase.init.success',
      metadata: <String, Object?>{
        'host': Uri.tryParse(_supabaseUrl)?.host ?? _supabaseUrl,
        'bucket': _supabaseStorageBucket,
      },
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Supabase initialization failed',
      error,
      stackTrace,
      event: 'supabase.init.failure',
      metadata: <String, Object?>{
        'host': Uri.tryParse(_supabaseUrl)?.host ?? _supabaseUrl,
      },
    );
  }
}

Future<void> _configureFirebaseRuntime(AppFlavor flavor) async {
  AuthRuntimeController.setCurrent(
    const AuthRuntimeState.unavailable(
      reason: 'Phone OTP is unavailable in this runtime.',
    ),
  );
  if (Firebase.apps.isEmpty) {
    AuthRuntimeController.setCurrent(
      const AuthRuntimeState.unavailable(
        reason: 'Firebase is not configured in this runtime.',
      ),
    );
    return;
  }
  if (_emulatorsConfigured) {
    AuthRuntimeController.setCurrent(
      AuthRuntimeState.emulatorOnly(emulatorHost: _resolveEmulatorHost()),
    );
    return;
  }

  final useEmulators =
      flavor == AppFlavor.dev && kDebugMode && _useFirebaseEmulators;
  if (!useEmulators) {
    if (_enableLivePhoneAuth) {
      AuthRuntimeController.setCurrent(const AuthRuntimeState.live());
      AppLogger.info(
        'Live phone auth enabled for this build.',
        event: 'auth.runtime.live_enabled',
        metadata: <String, Object?>{'flavor': flavor.nameValue},
      );
      return;
    }
    AuthRuntimeController.setCurrent(
      const AuthRuntimeState.unavailable(
        reason:
            'Phone OTP is disabled for this build. Enable live auth with --dart-define=ENABLE_LIVE_PHONE_AUTH=true or use the Firebase Auth Emulator in dev.',
      ),
    );
    AppLogger.info(
      'Phone auth disabled for this build because live auth is not enabled.',
      event: 'auth.runtime.disabled',
      metadata: <String, Object?>{'flavor': flavor.nameValue},
    );
    return;
  }

  final host = _resolveEmulatorHost();
  final authEmulatorReachable = await isTcpPortReachable(host, 9099);
  if (!authEmulatorReachable) {
    AuthRuntimeController.setCurrent(
      AuthRuntimeState.unavailable(
        reason:
            'Firebase Auth Emulator is not reachable on $host:9099. Start firebase emulators:start or run the app with --dart-define=FIREBASE_EMULATOR_HOST=<LAN_IP> for a real phone.',
      ),
    );
    AppLogger.warning(
      'Firebase Auth emulator is not reachable on $host:9099. '
      'Phone OTP will remain unavailable instead of falling back to live Firebase.',
      event: 'auth.runtime.emulator_unreachable',
      metadata: <String, Object?>{'host': host, 'port': 9099},
    );
    return;
  }

  FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  FirebaseStorage.instance.useStorageEmulator(host, 9199);

  _emulatorsConfigured = true;
  AuthRuntimeController.setCurrent(
    AuthRuntimeState.emulatorOnly(emulatorHost: host),
  );
  AppLogger.info(
    'Firebase emulators enabled on $host (auth:9099, firestore:8080, functions:5001, storage:9199)',
    event: 'firebase.emulator.enabled',
    metadata: <String, Object?>{
      'host': host,
      'authPort': 9099,
      'firestorePort': 8080,
      'functionsPort': 5001,
      'storagePort': 9199,
    },
  );
}

Future<void> _configureCrashlytics(AppFlavor flavor) async {
  if (Firebase.apps.isEmpty) {
    return;
  }
  final enabled = kReleaseMode || _enableCrashlyticsInDebug;
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
    if (!enabled) {
      AppLogger.info(
        'Crashlytics disabled in debug. Enable with --dart-define=CRASHLYTICS_IN_DEBUG=true',
        event: 'crashlytics.disabled.debug',
      );
      return;
    }
    await FirebaseCrashlytics.instance.setCustomKey(
      'app_flavor',
      flavor.nameValue,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Crashlytics setup failed',
      error,
      stackTrace,
      event: 'crashlytics.setup.failure',
    );
  }
}

Future<void> _recordFlutterFatalError(FlutterErrorDetails details) async {
  if (Firebase.apps.isEmpty) {
    return;
  }
  try {
    await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  } catch (error, stackTrace) {
    AppLogger.error(
      'Crashlytics record failed',
      error,
      stackTrace,
      event: 'crashlytics.record.flutter_failure',
    );
  }
}

Future<void> _recordError(
  Object error,
  StackTrace stackTrace, {
  required bool fatal,
}) async {
  if (Firebase.apps.isEmpty) {
    return;
  }
  try {
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
    );
  } catch (innerError, innerStackTrace) {
    AppLogger.error(
      'Crashlytics record failed',
      innerError,
      innerStackTrace,
      event: 'crashlytics.record.error_failure',
    );
  }
}

String _resolveEmulatorHost() {
  if (_firebaseEmulatorHostOverride.isNotEmpty) {
    return _firebaseEmulatorHostOverride;
  }
  if (kIsWeb) {
    return '127.0.0.1';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    // Android emulator cannot reach localhost on host machine directly.
    return '10.0.2.2';
  }
  return '127.0.0.1';
}
