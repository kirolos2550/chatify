import 'package:chatify/core/data/local/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

@module
abstract class AppModule {
  @lazySingleton
  Dio dio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  @lazySingleton
  FirebaseAuth firebaseAuth() => FirebaseAuth.instance;

  @lazySingleton
  FirebaseFirestore firebaseFirestore() => FirebaseFirestore.instance;

  @lazySingleton
  FirebaseStorage firebaseStorage() => FirebaseStorage.instance;

  @lazySingleton
  FirebaseFunctions firebaseFunctions() => FirebaseFunctions.instance;

  @lazySingleton
  FirebaseMessaging firebaseMessaging() => FirebaseMessaging.instance;

  @lazySingleton
  FlutterLocalNotificationsPlugin localNotificationsPlugin() =>
      FlutterLocalNotificationsPlugin();

  @lazySingleton
  FlutterSecureStorage secureStorage() => const FlutterSecureStorage();

  @lazySingleton
  Uuid uuid() => const Uuid();

  @lazySingleton
  AppDatabase appDatabase() => AppDatabase();
}
