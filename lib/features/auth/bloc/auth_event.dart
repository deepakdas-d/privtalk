abstract class AuthEvent {}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  LoginRequested(this.email, this.password);
}

class RegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String confirmPassword;
  final String name;
  final String phone;
  RegisterRequested(
    this.email,
    this.password,
    this.confirmPassword,
    this.name,
    this.phone,
  );
}
