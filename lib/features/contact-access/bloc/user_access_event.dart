abstract class UserAccessEvent {}

class LoadUserEvent extends UserAccessEvent {
  final String uid;

  LoadUserEvent(this.uid);
}
