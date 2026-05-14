import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/register_page.dart';

import '../features/call/bloc/call_bloc.dart';
import '../features/call/bloc/call_state.dart';
import '../features/call/models/call_model.dart';

import '../features/call/presentation/pages/incoming_call_page.dart';
import '../features/call/presentation/pages/outgoing_call_page.dart';

import '../features/call/repository/call_repository.dart';

import '../features/contact-access/presentation/user_access_page.dart';
import '../features/contact/presentation/pages/contact_page.dart';
import '../features/profile/presentation/profile_page.dart';

import '../utils/widgets/incoming_call_listner.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/home',

    redirect: (context, state) {
      final loggedIn = FirebaseAuth.instance.currentUser != null;

      final authRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!loggedIn && !authRoute) {
        return '/login';
      }

      if (loggedIn && authRoute) {
        return '/home';
      }

      return null;
    },

    routes: [
      // ─────────────────────────────────────────────────────
      // AUTH ROUTES
      // ─────────────────────────────────────────────────────
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),

      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),

      // ─────────────────────────────────────────────────────
      // AUTHENTICATED SHELL
      // ─────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) {
          return BlocProvider(
            create: (_) => CallBloc(repository: CallRepository()),

            child: IncomingCallListener(child: child),
          );
        },

        routes: [
          // HOME
          GoRoute(
            path: '/home',
            builder: (context, state) => const ContactsPage(),
          ),

          // PROFILE
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),

          // USER ACCESS
          GoRoute(
            path: '/user-profile',
            builder: (context, state) {
              final uid = state.extra as String;

              return UserAccessPage(uid: uid);
            },
          ),

          // OUTGOING CALL
          GoRoute(
            path: '/outgoing-call',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>;

              return BlocBuilder<CallBloc, CallState>(
                builder: (context, callState) {
                  final callId = switch (callState) {
                    CallOutgoing s => s.callId,
                    CallConnecting s => s.callId,
                    CallActive s => s.callId,
                    CallReconnecting s => s.callId,
                    _ => '',
                  };

                  return OutgoingCallPage(
                    callId: callId,
                    remoteUid: extra['remoteUid'] as String,
                    remoteName: extra['remoteName'] as String,
                    remotePhoto: extra['remotePhoto'] as String,
                    callType: extra['callType'] as CallType,
                  );
                },
              );
            },
          ),

          // INCOMING CALL
          GoRoute(
            path: '/incoming-call',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>;

              return IncomingCallPage(
                call: extra['call'] as CallModel,
                callerName: extra['callerName'] as String,
                callerPhoto: extra['callerPhoto'] as String,
              );
            },
          ),
        ],
      ),
    ],
  );
}
