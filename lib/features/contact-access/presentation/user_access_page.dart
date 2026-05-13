import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_bloc.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_event.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_state.dart';
import 'package:privtalk/features/contact-access/repository/user_access_repository.dart';

class UserAccessPage extends StatelessWidget {
  final String uid;

  const UserAccessPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => UserAccessBloc(
        repository: UserAccessRepository(firestore: FirebaseFirestore.instance),
      )..add(LoadUserEvent(uid)),

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

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // video call
                          },
                          icon: const Icon(Icons.videocam),
                          label: const Text('Video Call'),
                        ),
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // audio call
                          },
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
