import 'dart:async';

import 'package:chatify/app/app.dart';
import 'package:chatify/app/di/injection.dart';
import 'package:chatify/app/emulator_port_probe.dart';
import 'package:chatify/app/flavor.dart';
import 'package:chatify/app/localization/app_locale_controller.dart';
import 'package:chatify/core/common/app_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:chatify/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const bool _useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: true,
);
const String _firebaseEmulatorHostOverride = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
);

bool _emulatorsConfigured = false;

Future<void> bootstrap(AppFlavor flavor) async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      AppLogger.error('FlutterError', details.exception, details.stack);
    };

    await _initFirebase();
    await _configureFirebaseRuntime(flavor);
    await configureDependencies(flavor);
    await AppLocaleController.instance.load();
    runApp(ChatifyApp(flavor: flavor));
  }, (error, stackTrace) => AppLogger.error('ZoneError', error, stackTrace));
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
      AppLogger.error('Firebase initialization skipped', error, stackTrace);
    }
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
  );
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
