import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:privtalk/features/auth/repository/auth_repository.dart';

import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc(this.authRepository) : super(AuthInitial()) {
    on<LoginRequested>((event, emit) async {
      emit(AuthLoading());

      try {
        await authRepository.login(
          email: event.email,
          password: event.password,
        );

        emit(AuthSuccess());
      } catch (e) {
        emit(AuthFailure(e.toString()));
      }
    });

    on<RegisterRequested>((event, emit) async {
      emit(AuthLoading());

      try {
        final email = event.email.trim();
        final password = event.password.trim();
        final confirmPassword = event.confirmPassword.trim();
        final name = event.name.trim();
        final phone = event.phone.trim();

        // Empty checks
        if (name.isEmpty ||
            phone.isEmpty ||
            email.isEmpty ||
            password.isEmpty ||
            confirmPassword.isEmpty) {
          emit(AuthFailure('All fields are required'));
          return;
        }

        // Name validation
        if (name.length < 3) {
          emit(AuthFailure('Name must be at least 3 characters'));
          return;
        }

        if (!RegExp(r"^[a-zA-Z\s]+$").hasMatch(name)) {
          emit(AuthFailure('Name should contain only letters'));
          return;
        }

        // Email validation
        final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

        if (!emailRegex.hasMatch(email)) {
          emit(AuthFailure('Invalid email address'));
          return;
        }

        // Phone validation
        if (!RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
          emit(AuthFailure('Enter valid 10 digit phone number'));
          return;
        }

        // Password validation
        if (password.length < 8) {
          emit(AuthFailure('Password must be at least 8 characters'));
          return;
        }

        if (!RegExp(r'[A-Z]').hasMatch(password)) {
          emit(AuthFailure('Password must contain an uppercase letter'));
          return;
        }

        if (!RegExp(r'[a-z]').hasMatch(password)) {
          emit(AuthFailure('Password must contain a lowercase letter'));
          return;
        }

        if (!RegExp(r'[0-9]').hasMatch(password)) {
          emit(AuthFailure('Password must contain a number'));
          return;
        }

        if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
          emit(AuthFailure('Password must contain a special character'));
          return;
        }

        // Confirm password
        if (password != confirmPassword) {
          emit(AuthFailure('Passwords do not match'));
          return;
        }

        // Connectivity check
        final connectivity = await Connectivity().checkConnectivity();

        // Check if the list contains 'none' or is empty
        if (connectivity.contains(ConnectivityResult.none) ||
            connectivity.isEmpty) {
          emit(AuthFailure('No internet connection'));
          return;
        }

        final hasInternet = await InternetConnection().hasInternetAccess;

        if (!hasInternet) {
          emit(AuthFailure('Internet unavailable'));
          return;
        }

        // Register
        await authRepository.register(
          email: email,
          password: password,
          name: name,
          phone: phone,
        );

        emit(AuthSuccess());
      } catch (e) {
        final error = e.toString().toLowerCase();

        if (error.contains('email-already-in-use')) {
          emit(AuthFailure('Email already registered'));
        } else if (error.contains('network-request-failed')) {
          emit(AuthFailure('Network error occurred'));
        } else if (error.contains('weak-password')) {
          emit(AuthFailure('Weak password'));
        } else {
          emit(AuthFailure('Registration failed'));
        }
      }
    });
  }
}
