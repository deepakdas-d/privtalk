// lib/features/contacts/presentation/widgets/user_tile.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:privtalk/features/contact/models/user_model.dart';

class UserTile extends StatelessWidget {
  final UserModel user;

  const UserTile({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.push('/user-profile', extra: user),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF6C63FF),

        backgroundImage: user.photoUrl.isNotEmpty
            ? CachedNetworkImageProvider(user.photoUrl)
            : null,

        child: user.photoUrl.isEmpty
            ? Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(user.name),
      subtitle: Text(user.phone),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}
