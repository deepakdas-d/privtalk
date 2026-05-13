import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:privtalk/features/contact-access/model/app_user.dart';

class UserAccessRepository {
  final FirebaseFirestore firestore;

  UserAccessRepository({required this.firestore});

  Future<AppUser> fetchUser(String uid) async {
    final doc = await firestore.collection('users').doc(uid).get();

    if (!doc.exists) {
      throw Exception('User not found');
    }

    return AppUser.fromMap(doc.data()!, uid);
  }
}
