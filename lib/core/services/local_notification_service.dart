import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/call/repository/call_repository.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  final callId = response.payload;
  if (callId == null || callId.isEmpty) return;

  if (response.actionId == 'decline') {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      await CallRepository().declineCall(callId);
    } catch (e) {
      developer.log(
        'Error declining call in bg: $e',
        name: 'LocalNotification',
      );
    }
  }
}

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

  static String? pendingAnswerCallId;
  static String? pendingDeclineCallId;

  // ─── Channel IDs ───────────────────────────────────────────────────────────

  static const _callChannelId =
      'incoming_calls_v2'; // Changed to v2 to bypass channel cache for sound updates
  static const _callChannelName = 'Incoming Calls';
  static const _callChannelDesc =
      'Full-screen notifications for incoming calls';

  static const _missedChannelId = 'missed_calls';
  static const _missedChannelName = 'Missed Calls';
  static const _missedChannelDesc = 'Notifications for missed calls';

  static const _messageChannelId = 'messages_channel';
  static const _messageChannelName = 'Messages';
  static const _messageChannelDesc = 'Notifications for text messages';

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
      sound: RawResourceAndroidNotificationSound('custom_ringtone'),
      enableVibration: true,
    );

    const missedChannel = AndroidNotificationChannel(
      _missedChannelId,
      _missedChannelName,
      description: _missedChannelDesc,
      importance: Importance.high,
    );

    const messageChannel = AndroidNotificationChannel(
      _messageChannelId,
      _messageChannelName,
      description: _messageChannelDesc,
      importance: Importance.high,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(callChannel);
      await androidPlugin.createNotificationChannel(missedChannel);
      await androidPlugin.createNotificationChannel(messageChannel);
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
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
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
      sound:  RawResourceAndroidNotificationSound('custom_ringtone'),
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
          showsUserInterface: false,
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

  // ─── Show text message notification ──────────────────────────────────────────

  /// Shows a high-priority heads-up notification for text messages.
  static Future<void> showTextMessageNotification(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] != 'text_message') return;

    final senderName = data['senderName'] ?? 'Someone';
    final chatId = data['chatId'] ?? 'chat';

    // The FCM visual body could be in message.notification,
    // or we can fall back if it wasn't sent as a notification block.
    final body = message.notification?.body ?? 'New message';

    developer.log(
      '💬 Showing message notification | sender=$senderName',
      name: 'LocalNotification',
    );

    const androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: _messageChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: chatId
          .hashCode, // Unique ID per chat allows stacking/overwriting appropriately
      title: senderName,
      body: body,
      notificationDetails: details,
      payload: 'msg:$chatId', // Distinguish from call payloads
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
    final payload = response.payload;

    developer.log(
      '📱 Notification tapped | action=${response.actionId} | payload=$payload',
      name: 'LocalNotification',
    );

    if (payload == null || payload.isEmpty) return;

    if (payload.startsWith('msg:')) {
      final chatId = payload.substring(4);
      developer.log(
        '📱 Text message notification tapped for chat: $chatId',
        name: 'LocalNotification',
      );
      // Future: Navigate directly to the chat screen from here.
      return;
    }

    final callId = payload;

    if (response.actionId == 'answer') {
      pendingAnswerCallId = callId;
    } else if (response.actionId == 'decline') {
      pendingDeclineCallId = callId;
      CallRepository().declineCall(callId);
      cancelCallNotification();
    }

    // Delegate to IncomingCallListener's callback for navigation
    onCallNotificationTap?.call(callId);
  }
}
