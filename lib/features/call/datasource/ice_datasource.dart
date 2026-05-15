import 'dart:developer';

import 'package:dio/dio.dart';

class IceDatasource {
  static const _apiKey = 'f7c8aaf84364820ed38de9db5ff7cc50b85c';

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
      log('🔗 [ICE] Fetching TURN servers from Metered API', name: 'IceDatasource');
      final response = await _dio.get(
        _url,
        queryParameters: {'apiKey': _apiKey},
      );

      if (response.statusCode == 200 && response.data is List) {
        final servers = List<Map<String, dynamic>>.from(response.data);
        log('✅ [ICE] TURN servers fetched successfully | count=${servers.length}', name: 'IceDatasource');
        for (int i = 0; i < servers.length; i++) {
          final server = servers[i];
          log('  ├─ Server $i: ${server['urls']} | username=${server['username'] != null ? "***" : "none"}', name: 'IceDatasource');
        }
        return servers;
      }
    } on DioException catch (e) {
      log('⚠️ [ICE] Metered API error: ${e.message} | statusCode=${e.response?.statusCode}', name: 'IceDatasource');
    } catch (e) {
      log('❌ [ICE] Unexpected error: $e', name: 'IceDatasource');
    }

    // Fallback: Google STUN only
    log('🔗 [ICE] Using fallback: Google STUN server only', name: 'IceDatasource');
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
  }
}
