import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'local_notification_service.dart';

/// Top-level handler required by FCM for background/killed state.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log(
    '🔔 [FCM-BG] ========== BACKGROUND MESSAGE RECEIVED ==========',
    name: 'NotificationService',
  );
  developer.log(
    '🔔 [FCM-BG] data=${message.data} | messageId=${message.messageId}',
    name: 'NotificationService',
  );
  await LocalNotificationService.showCallNotification(message);
  developer.log(
    '🔔 [FCM-BG] ✅ Background handler completed',
    name: 'NotificationService',
  );
}

class NotificationService {
  NotificationService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Call once from main.dart after Firebase.initializeApp().
  static Future<void> initialize() async {
    developer.log('🔔 [FCM] Initializing NotificationService...', name: 'NotificationService');
    await _saveToken();
    _listenTokenRefresh();
    _listenForeground();
    _listenBackgroundTap();
    _listenKilledStateTap();
    developer.log('🔔 [FCM] ✅ NotificationService initialized', name: 'NotificationService');
  }

  // ─── Permission ────────────────────────────────────────────────────────────

  /// Call this after login to ensure Firebase knows about the granted permission
  static Future<void> requestPermission() async {
    developer.log('🔔 [FCM] Requesting notification permission...', name: 'NotificationService');
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );
    developer.log(
      '🔔 [FCM] Permission status: ${settings.authorizationStatus}',
      name: 'NotificationService',
    );
  }

  // ─── Token ─────────────────────────────────────────────────────────────────

  static Future<void> _saveToken() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      developer.log('🔔 [FCM] ⚠️ _saveToken skipped — no user logged in', name: 'NotificationService');
      return;
    }
    final token = await _fcm.getToken();
    if (token == null) {
      developer.log('🔔 [FCM] ⚠️ _saveToken skipped — FCM token is null', name: 'NotificationService');
      return;
    }
    developer.log(
      '🔔 [FCM] Saving token | uid=$uid | token=${token.substring(0, 20)}...',
      name: 'NotificationService',
    );
    await _firestore.collection('users').doc(uid).update({'fcmToken': token});
    developer.log('🔔 [FCM] ✅ Token saved to Firestore', name: 'NotificationService');
  }

  static void _listenTokenRefresh() {
    _fcm.onTokenRefresh.listen((newToken) async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      await _firestore.collection('users').doc(uid).update({
        'fcmToken': newToken,
      });
    });
  }

  // ─── Message listeners ─────────────────────────────────────────────────────

  /// App is open and in foreground.
  static void _listenForeground() {
    developer.log('🔔 [FCM] Foreground listener registered', name: 'NotificationService');
    FirebaseMessaging.onMessage.listen((message) async {
      final type = message.data['type'];
      developer.log(
        '🔔 [FCM-FG] ========== FOREGROUND MESSAGE ==========',
        name: 'NotificationService',
      );
      developer.log(
        '🔔 [FCM-FG] type=$type | data=${message.data} | msgId=${message.messageId}',
        name: 'NotificationService',
      );
      if (type == 'incoming_call') {
        developer.log('🔔 [FCM-FG] Showing call notification...', name: 'NotificationService');
        await LocalNotificationService.showCallNotification(message);
        developer.log('🔔 [FCM-FG] ✅ Call notification shown', name: 'NotificationService');
      } else {
        developer.log('🔔 [FCM-FG] Type "$type" — no action', name: 'NotificationService');
      }
    });
  }

  /// App was in background, user tapped the notification.
  static void _listenBackgroundTap() {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  /// App was killed, user tapped the notification that launched the app.
  static void _listenKilledStateTap() async {
    final initial = await _fcm.getInitialMessage();
    developer.log(
      '🔔 [FCM] Killed-state initial message: ${initial?.data ?? 'none'}',
      name: 'NotificationService',
    );
    if (initial != null) {
      _handleNotificationTap(initial);
    }
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'];
    final callId = message.data['callId'];
    developer.log(
      '🔔 [FCM-TAP] Notification tapped | type=$type | callId=$callId',
      name: 'NotificationService',
    );
    if (type == 'incoming_call' && callId != null) {
      developer.log('🔔 [FCM-TAP] Deferring to IncomingCallListener', name: 'NotificationService');
    }
  }
}
