import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;

/// Service responsible for sending FCM HTTP v1 notifications.
///
/// ⚠️ MVP WARNING:
/// This uses a Firebase service account JSON directly inside the app.
/// That is NOT secure for production.
///
/// In production:
/// - Move FCM sending to backend / Cloud Functions
/// - Never expose service-account.json inside mobile apps
class FcmSenderService {
  FcmSenderService._();

  /// Firebase project id
  static const String _projectId = 'privtalk-4f668';

  /// Path to service account json inside assets/
  static const String _serviceAccountPath = 'assets/service-account.json';

  /// FCM HTTP v1 endpoint
  static final String _fcmEndpoint =
      'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';

  /// Shared Dio instance
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Generates OAuth access token using Firebase service account.
  ///
  /// FCM HTTP v1 API requires Bearer token authentication.
  static Future<String> _getAccessToken() async {
    try {
      developer.log(
        '🔑 [FCM] Loading service account from $_serviceAccountPath',
        name: 'FcmSender',
      );

      /// Load service account json from assets
      final jsonString = await rootBundle.loadString(_serviceAccountPath);

      developer.log(
        '🔑 [FCM] Service account loaded (${jsonString.length} chars)',
        name: 'FcmSender',
      );

      /// Parse credentials
      final credentials = auth.ServiceAccountCredentials.fromJson(
        json.decode(jsonString),
      );

      /// Required FCM scope
      const scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      developer.log(
        '🔑 [FCM] Requesting OAuth token with scopes: $scopes',
        name: 'FcmSender',
      );

      /// Create authenticated client
      final client = await auth.clientViaServiceAccount(credentials, scopes);

      /// Extract token
      final accessToken = client.credentials.accessToken.data;
      final expiry = client.credentials.accessToken.expiry;

      developer.log(
        '🔑 [FCM] ✅ OAuth token obtained | expires=$expiry | token=${accessToken.substring(0, 20)}...',
        name: 'FcmSender',
      );

      client.close();

      return accessToken;
    } catch (e, stackTrace) {
      developer.log(
        '🔑 [FCM] ❌ Failed to generate access token: $e',
        name: 'FcmSender',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to generate FCM access token: $e');
    }
  }

  /// Common POST request handler for FCM
  ///
  /// Avoids duplicating request logic.
  static Future<void> _sendMessage({
    required Map<String, dynamic> message,
  }) async {
    try {
      developer.log(
        '📤 [FCM] ========== SENDING FCM MESSAGE ==========',
        name: 'FcmSender',
      );
      developer.log(
        '📤 [FCM] Target token: ${(message['token'] as String?)?.substring(0, 20)}...',
        name: 'FcmSender',
      );
      developer.log(
        '📤 [FCM] Payload: ${json.encode(message)}',
        name: 'FcmSender',
      );
      developer.log(
        '📤 [FCM] Endpoint: $_fcmEndpoint',
        name: 'FcmSender',
      );

      final accessToken = await _getAccessToken();

      developer.log(
        '📤 [FCM] Sending POST request...',
        name: 'FcmSender',
      );

      final response = await _dio.post(
        _fcmEndpoint,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        data: {'message': message},
      );

      developer.log(
        '📤 [FCM] ✅ FCM response | status=${response.statusCode} | data=${response.data}',
        name: 'FcmSender',
      );
    } on DioException catch (e, stackTrace) {
      developer.log(
        '📤 [FCM] ❌ DioException | status=${e.response?.statusCode} | data=${e.response?.data} | message=${e.message}',
        name: 'FcmSender',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('FCM request failed: ${e.response?.data ?? e.message}');
    } catch (e, stackTrace) {
      developer.log(
        '📤 [FCM] ❌ Unexpected error: $e',
        name: 'FcmSender',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Unexpected FCM error: $e');
    }
  }

  /// Sends silent/data-only incoming call push notification.
  ///
  /// Receiver app handles:
  /// - Full-screen incoming call UI
  /// - Ringtone
  /// - Call navigation
  /// - Accept/reject logic
  ///
  /// No system tray notification is shown.
  static Future<void> sendIncomingCall({
    required String receiverFcmToken,
    required String callId,
    required String callerName,
    required String callerId,
  }) async {
    developer.log(
      '📞 [FCM] sendIncomingCall() | callId=$callId | caller=$callerName ($callerId) | token=${receiverFcmToken.substring(0, 20)}...',
      name: 'FcmSender',
    );

    await _sendMessage(
      message: {
        'token': receiverFcmToken,

        /// Data-only payload
        'data': {
          'type': 'incoming_call',
          'callId': callId,
          'callerName': callerName,
          'callerId': callerId,
        },

        /// Android specific config
        'android': {'priority': 'high'},

        /// iOS specific config
        'apns': {
          'payload': {
            'aps': {
              'sound': 'custom_ringtone.wav',
            }
          },
          'headers': {'apns-priority': '10', 'apns-push-type': 'voip'},
        },
      },
    );

    developer.log(
      '📞 [FCM] ✅ sendIncomingCall() completed successfully',
      name: 'FcmSender',
    );
  }

  /// Sends visible missed-call notification.
  ///
  /// Unlike incoming call push,
  /// this shows inside notification tray.
  static Future<void> sendMissedCall({
    required String receiverFcmToken,
    required String callerName,
    required String callId,
  }) async {
    developer.log(
      '📞 [FCM] sendMissedCall() | callId=$callId | caller=$callerName | token=${receiverFcmToken.substring(0, 20)}...',
      name: 'FcmSender',
    );

    await _sendMessage(
      message: {
        'token': receiverFcmToken,

        /// Visible notification
        'notification': {
          'title': 'Missed call',
          'body': '$callerName called you',
        },

        /// Extra app data
        'data': {
          'type': 'missed_call',
          'callerName': callerName,
          'callId': callId,
        },

        /// Android notification settings
        'android': {
          'notification': {
            'channel_id': 'missed_calls',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      },
    );

    developer.log(
      '📞 [FCM] ✅ sendMissedCall() completed successfully',
      name: 'FcmSender',
    );
  }
}
