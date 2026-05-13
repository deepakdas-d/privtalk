class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String photoUrl;

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.photoUrl,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
    );
  }
}
