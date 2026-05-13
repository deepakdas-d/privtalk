import 'package:privtalk/features/auth/model/auth_model.dart';

abstract class ProfileState {}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final UserModel user;
  ProfileLoaded(this.user);
}

class ProfileUpdating extends ProfileState {
  final UserModel user;
  ProfileUpdating(this.user);
}

class ProfileUpdateSuccess extends ProfileState {
  final UserModel user;
  ProfileUpdateSuccess(this.user);
}

class ProfilePhotoUploading extends ProfileState {
  final UserModel user;
  ProfilePhotoUploading(this.user);
}

class ProfilePhotoUploadSuccess extends ProfileState {
  final UserModel user;
  final String photoUrl;
  ProfilePhotoUploadSuccess(this.user, this.photoUrl);
}

class ProfileFailure extends ProfileState {
  final String message;
  final UserModel? user;
  ProfileFailure(this.message, {this.user});
}
