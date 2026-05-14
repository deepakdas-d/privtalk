import 'dart:developer';

import 'package:dio/dio.dart';

class IceDatasource {
  static const _apiKey = ' f7c8aaf84364820ed38de9db5ff7cc50b85c';

  static const _url = 'https://newworld.metered.live/api/v1/turn/credentials';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  /// Returns the full iceServers list from Metered.
  /// Falls back to Google STUN only if the request fails.
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    try {
      final response = await _dio.get(
        _url,
        queryParameters: {'apiKey': _apiKey},
      );

      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
    } on DioException catch (e) {
      log('ICE fetch error: ${e.message}');
    } catch (e) {
      log('Unexpected ICE fetch error: $e');
    }

    // Fallback: Google STUN only
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
  }
}
