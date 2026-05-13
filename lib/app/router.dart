import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:privtalk/features/auth/presentation/pages/login_page.dart';
import 'package:privtalk/features/auth/presentation/pages/register_page.dart';
import 'package:privtalk/features/contact/presentation/pages/contact_page.dart';
import 'package:privtalk/features/profile/presentation/profile_page.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: FirebaseAuth.instance.currentUser != null
        ? '/home'
        : '/login',

    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const ContactsPage()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
    ],
  );
}
