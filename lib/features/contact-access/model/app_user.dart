class AppUser {
  final String uid;
  final String name;
  final String phone;
  final String photoUrl;

  AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.photoUrl,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
    );
  }
}
