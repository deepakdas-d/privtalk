import 'package:privtalk/features/contact-access/model/app_user.dart';

abstract class UserAccessState {}

class UserAccessInitial extends UserAccessState {}

class UserAccessLoading extends UserAccessState {}

class UserAccessLoaded extends UserAccessState {
  final AppUser user;

  UserAccessLoaded(this.user);
}

class UserAccessError extends UserAccessState {
  final String message;

  UserAccessError(this.message);
}
