import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/session_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Background FCM handler (must be registered before runApp)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 3. Local notifications (channels, tap handler)
  await LocalNotificationService.initialize();

  // 4. FCM permissions, token save, foreground/tap listeners
  await NotificationService.initialize();

  Bloc.observer = AppBlocObserver();

  SessionService.instance.initialize();

  runApp(const App());
}
