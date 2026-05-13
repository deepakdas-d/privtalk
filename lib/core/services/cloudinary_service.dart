import 'dart:io';
import 'package:dio/dio.dart';

class CloudinaryService {
  static const _cloudName = 'ds5bn67v3';
  static const _uploadPreset = 'privtalk_profiles';
  static const _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  static final _dio = Dio();

  static Future<String> uploadProfilePhoto(File file) async {
    final size = await file.length();
    if (size > _maxFileSizeBytes) {
      throw Exception(
        'Image exceeds the 5 MB limit. Please choose a smaller image.',
      );
    }

    final formData = FormData.fromMap({
      'upload_preset': _uploadPreset,
      'folder': 'profile_photos',
      'transformation': 'c_fill,w_400,h_400,q_auto,f_auto',
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });

    final response = await _dio.post(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        validateStatus: (status) => true, // handle errors manually
      ),
    );

    if (response.statusCode != 200) {
      final msg =
          response.data?['error']?['message'] ?? 'Cloudinary upload failed';
      throw Exception(msg);
    }

    return response.data['secure_url'] as String;
  }
}
