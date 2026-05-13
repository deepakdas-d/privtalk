import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:privtalk/features/auth/model/auth_model.dart';
import 'package:privtalk/features/profile/repository/profile_repository.dart';
import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository profileRepository;

  ProfileBloc(this.profileRepository) : super(ProfileInitial()) {
    on<LoadProfile>(_onLoad);
    on<UpdateProfile>(_onUpdate);
    on<UploadProfilePhoto>(_onUploadPhoto);
  }

  UserModel? _currentUser() {
    final s = state;
    if (s is ProfileLoaded) return s.user;
    if (s is ProfileUpdateSuccess) return s.user;
    if (s is ProfileUpdating) return s.user;
    if (s is ProfilePhotoUploading) return s.user;
    if (s is ProfilePhotoUploadSuccess) return s.user;
    if (s is ProfileFailure) return s.user;
    return null;
  }

  Future<void> _onLoad(LoadProfile event, Emitter emit) async {
    emit(ProfileLoading());
    try {
      final user = await profileRepository.getUserProfile();
      user != null
          ? emit(ProfileLoaded(user))
          : emit(ProfileFailure('User not found'));
    } catch (e) {
      emit(ProfileFailure(e.toString()));
    }
  }

  Future<void> _onUpdate(UpdateProfile event, Emitter emit) async {
    final current = _currentUser();
    if (current == null) return;

    emit(ProfileUpdating(current));
    try {
      await profileRepository.updateProfile(
        name: event.name,
        phone: event.phone,
        photoUrl: event.photoUrl,
      );
      final updated = current.copyWith(
        name: event.name,
        phone: event.phone,
        photoUrl: event.photoUrl,
      );
      emit(ProfileUpdateSuccess(updated));
    } catch (e) {
      emit(ProfileFailure(e.toString(), user: current));
    }
  }

  Future<void> _onUploadPhoto(UploadProfilePhoto event, Emitter emit) async {
    final current = _currentUser();
    if (current == null) return;

    emit(ProfilePhotoUploading(current));
    try {
      final url = await profileRepository.uploadAndSavePhoto(
        File(event.filePath),
      );
      final updated = current.copyWith(photoUrl: url);
      emit(ProfilePhotoUploadSuccess(updated, url));
      emit(ProfileLoaded(updated)); // settle back to loaded so UI is consistent
    } catch (e) {
      emit(ProfileFailure(e.toString(), user: current));
    }
  }
}
