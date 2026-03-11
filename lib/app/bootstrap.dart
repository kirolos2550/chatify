import 'dart:async';

import 'package:chatify/app/app.dart';
import 'package:chatify/app/di/injection.dart';
import 'package:chatify/app/emulator_port_probe.dart';
import 'package:chatify/app/flavor.dart';
import 'package:chatify/app/localization/app_locale_controller.dart';
import 'package:chatify/app/router/app_router.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/network/firebase_paths.dart';
import 'package:chatify/core/notifications/chat_local_notifications.dart';
import 'package:chatify/core/notifications/message_notification_orchestrator.dart';
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
AppLifecycleListener? _lifecycleListener;
Timer? _uiHangWatchdog;
DateTime? _uiHangLastTick;
const Duration _uiHangProbeInterval = Duration(milliseconds: 700);
const Duration _uiHangThreshold = Duration(seconds: 4);
StreamSubscription<User?>? _incomingCallAuthSubscription;
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
_incomingCallSubscription;
final Set<String> _notifiedIncomingCallIds = <String>{};

Future<void> bootstrap(AppFlavor flavor) async {
  await runZonedGuarded(
    () async {
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
      await AppLocaleController.instance.load();
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
    await notifications.initialize();
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
  if (Firebase.apps.isEmpty) {
    return;
  }
  if (_emulatorsConfigured) {
    return;
  }

  final useEmulators =
      flavor == AppFlavor.dev && kDebugMode && _useFirebaseEmulators;
  if (!useEmulators) {
    return;
  }

  final host = _resolveEmulatorHost();
  final authEmulatorReachable = await isTcpPortReachable(host, 9099);
  if (!authEmulatorReachable) {
    AppLogger.info(
      'Firebase Auth emulator is not reachable on $host:9099. '
      'Falling back to live Firebase services.',
      event: 'firebase.emulator.auth.unreachable',
      metadata: <String, Object?>{'host': host, 'port': 9099},
    );
    return;
  }

  FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  FirebaseStorage.instance.useStorageEmulator(host, 9199);

  _emulatorsConfigured = true;
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
