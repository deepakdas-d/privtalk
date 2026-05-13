import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:privtalk/utils/widgets/auth_field.dart';
import '../../bloc/auth_bloc.dart';
import '../../bloc/auth_event.dart';
import '../../bloc/auth_state.dart';
import '../../repository/auth_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
                    const SizedBox(height: 20),
                    _buildHeader(),
                    const SizedBox(height: 40),
                    AuthField(
                      controller: _name,
                      hint: 'Full name',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    AuthField(
                      controller: _phone,
                      hint: 'Phone number',
                      icon: Icons.phone_outlined,
                      keyboard: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    AuthField(
                      controller: _email,
                      hint: 'Email address',
                      icon: Icons.mail_outline_rounded,
                      keyboard: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    AuthField(
                      controller: _password,
                      hint: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscure: true,
                    ),
                    const SizedBox(height: 14),
                    AuthField(
                      controller: _confirmPassword,
                      hint: 'Confirm password',
                      icon: Icons.lock_reset_rounded,
                      obscure: true,
                    ),
                    const SizedBox(height: 32),
                    _buildRegisterButton(context, state),
                    const SizedBox(height: 20),
                    _buildLoginLink(context),
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
          Icons.person_add_alt_1_rounded,
          color: Color(0xFF6C63FF),
          size: 24,
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Create\naccount.',
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
        'Fill in the details to get started',
        style: TextStyle(color: Color(0xFF8888AA), fontSize: 15),
      ),
    ],
  );

  Widget _buildRegisterButton(BuildContext context, AuthState state) =>
      ElevatedButton(
        onPressed: state is AuthLoading
            ? null
            : () => context.read<AuthBloc>().add(
                RegisterRequested(
                  _email.text.trim(),
                  _password.text.trim(),
                  _confirmPassword.text.trim(),
                  _name.text.trim(),
                  _phone.text.trim(),
                ),
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
            : const Text('Create Account'),
      );

  Widget _buildLoginLink(BuildContext context) => Center(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Already have an account?",
          style: TextStyle(color: Color(0xFF8888AA), fontSize: 14),
        ),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
}
