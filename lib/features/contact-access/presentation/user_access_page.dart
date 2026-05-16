import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_bloc.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_event.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_state.dart';
import 'package:privtalk/features/contact-access/repository/user_access_repository.dart';
import 'package:privtalk/features/call/bloc/call_bloc.dart';
import 'package:privtalk/features/call/bloc/call_event.dart';
import 'package:privtalk/features/call/bloc/call_state.dart';
import 'package:privtalk/features/call/models/call_model.dart';

class UserAccessPage extends StatelessWidget {
  final String uid;

  const UserAccessPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    // Only provide UserAccessBloc here.
    // CallBloc is already provided by the ShellRoute in router.dart —
    // creating a duplicate was causing bugs 1 & 3 (separate instance meant
    // OutgoingCallPage read from an empty/uninitialised CallBloc).
    return BlocProvider(
      create: (_) => UserAccessBloc(
        repository: UserAccessRepository(
          firestore: FirebaseFirestore.instance,
        ),
      )..add(LoadUserEvent(uid)),
      child: _UserAccessView(uid: uid),
    );
  }
}

class _UserAccessView extends StatelessWidget {
  final String uid;

  const _UserAccessView({required this.uid});

  String get _currentUid => FirebaseAuth.instance.currentUser!.uid;

  void _startCall(
    BuildContext context,
    CallType type,
    String remoteName,
    String remotePhoto,
  ) {
    // Trigger the call in the Bloc
    context.read<CallBloc>().add(
      StartCallEvent(callerId: _currentUid, receiverId: uid, callType: type),
    );

    // Navigate immediately — the page listens to Bloc state for the callId
    context.push(
      '/outgoing-call',
      extra: {
        'remoteUid': uid,
        'remoteName': remoteName,
        'remotePhoto': remotePhoto,
        'callType': type,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CallBloc, CallState>(
      listener: (context, state) {
        // If call fails before we even navigate away, show a snackbar
        if (state is CallFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Call failed: ${state.reason}')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('User Profile')),
        body: BlocBuilder<UserAccessBloc, UserAccessState>(
          builder: (context, state) {
            if (state is UserAccessLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is UserAccessError) {
              return Center(child: Text(state.message));
            }

            if (state is UserAccessLoaded) {
              final user = state.user;

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.deepPurple,
                        backgroundImage: user.photoUrl.isNotEmpty
                            ? NetworkImage(user.photoUrl)
                            : null,
                        child: user.photoUrl.isEmpty
                            ? Text(
                                user.name.isNotEmpty
                                    ? user.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 40,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),

                      const SizedBox(height: 20),

                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(user.phone),
                      const SizedBox(height: 40),

                      // Video call button
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          onPressed: () => _startCall(
                            context,
                            CallType.video,
                            user.name,
                            user.photoUrl,
                          ),
                          icon: const Icon(Icons.videocam),
                          label: const Text('Video Call'),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Audio call button
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton.icon(
                          onPressed: () => _startCall(
                            context,
                            CallType.audio,
                            user.name,
                            user.photoUrl,
                          ),
                          icon: const Icon(Icons.call),
                          label: const Text('Audio Call'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return const SizedBox();
          },
        ),
      ),
    );
  }
}
