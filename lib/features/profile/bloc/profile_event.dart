abstract class ProfileEvent {}

class LoadProfile extends ProfileEvent {}

class UpdateProfile extends ProfileEvent {
  final String name;
  final String phone;
  final String? photoUrl;

  UpdateProfile({required this.name, required this.phone, this.photoUrl});
}

class UploadProfilePhoto extends ProfileEvent {
  final String filePath;
  UploadProfilePhoto({required this.filePath});
}
