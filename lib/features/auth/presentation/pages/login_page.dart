import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../bloc/auth_bloc.dart';
import '../../bloc/auth_event.dart';
import '../../bloc/auth_state.dart';
import '../../repository/auth_repository.dart';
import 'package:privtalk/utils/widgets/auth_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthRepository()),
      child: Scaffold(
        body: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthSuccess) context.go('/home');
            if (state is AuthFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: const Color(0xFFFF5F7E),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          },
          builder: (context, state) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    _buildHeader(),
                    const SizedBox(height: 48),
                    AuthField(
                      controller: _email,
                      hint: 'Email address',
                      icon: Icons.mail_outline_rounded,
                    ),
                    const SizedBox(height: 16),
                    AuthField(
                      controller: _password,
                      hint: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscure: true,
                    ),
                    const SizedBox(height: 32),
                    _buildLoginButton(context, state),
                    const SizedBox(height: 20),
                    _buildRegisterLink(context),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.lock_person_rounded,
          color: Color(0xFF6C63FF),
          size: 24,
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Welcome\nback.',
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: Color(0xFFF0F0FF),
          height: 1.1,
          letterSpacing: -1.5,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Sign in to continue',
        style: TextStyle(color: Color(0xFF8888AA), fontSize: 15),
      ),
    ],
  );

  Widget _buildLoginButton(BuildContext context, AuthState state) =>
      ElevatedButton(
        onPressed: state is AuthLoading
            ? null
            : () => context.read<AuthBloc>().add(
                LoginRequested(_email.text.trim(), _password.text.trim()),
              ),
        child: state is AuthLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text('Sign In'),
      );

  Widget _buildRegisterLink(BuildContext context) => Center(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Don't have an account?",
          style: TextStyle(color: Color(0xFF8888AA), fontSize: 14),
        ),
        TextButton(
          onPressed: () => context.go('/register'),
          child: const Text('Create one'),
        ),
      ],
    ),
  );
}
