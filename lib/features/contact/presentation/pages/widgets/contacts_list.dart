// lib/features/contacts/presentation/widgets/contacts_list.dart
import 'package:flutter/material.dart';
import 'package:privtalk/features/contact/models/user_model.dart';
import 'package:privtalk/features/contact/presentation/pages/widgets/user_tile.dart';

class ContactsList extends StatelessWidget {
  final List<UserModel> users;

  const ContactsList({super.key, required this.users});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (_, index) => UserTile(user: users[index]),
    );
  }
}
