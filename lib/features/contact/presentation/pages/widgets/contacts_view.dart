// lib/features/contacts/presentation/widgets/contacts_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:privtalk/features/contact/bloc/users_bloc.dart';
import 'package:privtalk/features/contact/bloc/users_state.dart';
import 'package:privtalk/features/contact/presentation/pages/widgets/contacts_empty.dart';
import 'package:privtalk/features/contact/presentation/pages/widgets/contacts_error.dart';
import 'package:privtalk/features/contact/presentation/pages/widgets/contacts_list.dart';

class ContactsView extends StatelessWidget {
  final VoidCallback onProfileTap;

  const ContactsView({super.key, required this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: onProfileTap,
            tooltip: 'Profile',
          ),
        ],
      ),
      body: BlocBuilder<UsersBloc, UsersState>(
        builder: (context, state) => switch (state) {
          UsersLoading() => const _LoadingView(),
          UsersLoaded(users: final u) when u.isEmpty => const ContactsEmpty(),
          UsersLoaded(users: final u) => ContactsList(users: u),
          UsersError(message: final m) => ContactsError(message: m),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
