class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String photoUrl;
  final bool isOnline;

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.photoUrl,
    this.isOnline = false,
  });

  UserModel copyWith({bool? isOnline}) {
    return UserModel(
      uid: uid,
      name: name,
      phone: phone,
      photoUrl: photoUrl,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
    );
  }
}
