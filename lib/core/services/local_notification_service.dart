import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles local notification channels, full-screen call notifications,
/// and notification tap callbacks.
///
/// Initialised once from main.dart before runApp().
class LocalNotificationService {
  LocalNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Callback invoked when the user taps a call notification.
  /// Set by IncomingCallListener so it can navigate without coupling
  /// this service to BuildContext / router.
  static void Function(String callId)? onCallNotificationTap;

  // ─── Channel IDs ───────────────────────────────────────────────────────────

  static const _callChannelId = 'incoming_calls_v2'; // Changed to v2 to bypass channel cache for sound updates
  static const _callChannelName = 'Incoming Calls';
  static const _callChannelDesc =
      'Full-screen notifications for incoming calls';

  static const _missedChannelId = 'missed_calls';
  static const _missedChannelName = 'Missed Calls';
  static const _missedChannelDesc = 'Notifications for missed calls';

  // ─── Notification IDs ──────────────────────────────────────────────────────

  static const _callNotificationId = 888;

  // ─── Initialize ────────────────────────────────────────────────────────────

  /// Creates Android notification channels and sets up tap handler.
  static Future<void> initialize() async {
    // Android channels
    const callChannel = AndroidNotificationChannel(
      _callChannelId,
      _callChannelName,
      description: _callChannelDesc,
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('custom_ringtone'),
      enableVibration: true,
    );

    const missedChannel = AndroidNotificationChannel(
      _missedChannelId,
      _missedChannelName,
      description: _missedChannelDesc,
      importance: Importance.high,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(callChannel);
      await androidPlugin.createNotificationChannel(missedChannel);
    }

    // Initialization settings
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    developer.log(
      '✅ LocalNotificationService initialized',
      name: 'LocalNotification',
    );
  }

  // ─── Show incoming call notification ───────────────────────────────────────

  /// Shows a high-priority notification with full-screen intent
  /// when an incoming_call FCM message arrives.
  ///
  /// Called from both foreground listener and background handler.
  static Future<void> showCallNotification(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];

    if (type != 'incoming_call') return;

    final callerName = data['callerName'] ?? 'Unknown';
    final callId = data['callId'] ?? '';

    developer.log(
      '📱 Showing call notification | caller=$callerName | callId=$callId',
      name: 'LocalNotification',
    );

    const androidDetails = AndroidNotificationDetails(
      _callChannelId,
      _callChannelName,
      channelDescription: _callChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('custom_ringtone'),
      enableVibration: true,
      // Action buttons
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'answer',
          'Answer',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'decline',
          'Decline',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: _callNotificationId,
      title: 'Incoming Call',
      body: '$callerName is calling you',
      notificationDetails: details,
      payload: callId,
    );
  }

  // ─── Cancel call notification ──────────────────────────────────────────────

  /// Dismiss the ongoing call notification (e.g. when the call is answered
  /// or the caller hangs up).
  static Future<void> cancelCallNotification() async {
    await _plugin.cancel(id: _callNotificationId);
  }

  // ─── Tap handler ───────────────────────────────────────────────────────────

  static void _onNotificationTap(NotificationResponse response) {
    final callId = response.payload;

    developer.log(
      '📱 Notification tapped | action=${response.actionId} | callId=$callId',
      name: 'LocalNotification',
    );

    if (callId == null || callId.isEmpty) return;

    // Delegate to IncomingCallListener's callback for navigation
    onCallNotificationTap?.call(callId);
  }
}
