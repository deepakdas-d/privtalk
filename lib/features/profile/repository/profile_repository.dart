import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:privtalk/features/auth/model/auth_model.dart';
import 'package:privtalk/core/services/cloudinary_service.dart';

class ProfileRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<UserModel?> getUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!, user.uid);
  }

  Future<void> updateProfile({
    required String name,
    required String phone,
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final data = <String, dynamic>{'name': name, 'phone': phone};
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    await _firestore.collection('users').doc(user.uid).update(data);
  }

  /// Compresses [file], uploads to Cloudinary, saves URL to Firestore.
  Future<String> uploadAndSavePhoto(File file) async {
    try {
      log('ORIGINAL FILE: ${file.path}');

      final compressed = await _compressImage(file);

      log('COMPRESSED FILE: ${compressed.path}');

      final url = await CloudinaryService.uploadProfilePhoto(compressed);

      log('CLOUDINARY URL: $url');

      if (url.isEmpty) {
        throw Exception('Image upload failed');
      }

      final user = _auth.currentUser;

      if (user == null) {
        throw Exception('User not authenticated');
      }

      await _firestore.collection('users').doc(user.uid).update({
        'photoUrl': url,
      });

      log('FIRESTORE UPDATED');

      return url;
    } catch (e, stack) {
      log('REPOSITORY ERROR: $e');
      print(stack);

      rethrow;
    }
  }

  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();

    final targetPath = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 75,
      minWidth: 400,
      minHeight: 400,
      format: CompressFormat.jpeg,
    );

    if (result == null) {
      throw Exception('Image compression failed');
    }

    return File(result.path);
  }
}
