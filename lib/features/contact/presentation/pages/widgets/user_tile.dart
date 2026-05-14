import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:privtalk/core/services/presence_service.dart';
import 'package:privtalk/features/contact/models/user_model.dart';

class UserTile extends StatelessWidget {
  final UserModel user;

  const UserTile({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: PresenceService.instance.userPresence(user.uid),

      builder: (context, snapshot) {
        final online = snapshot.data ?? false;

        return ListTile(
          onTap: () => context.push('/user-profile', extra: user.uid),

          leading: Stack(
            children: [
              CircleAvatar(
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

              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,

                  decoration: BoxDecoration(
                    color: online ? Colors.green : Colors.grey,

                    shape: BoxShape.circle,

                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),

          title: Text(user.name),

          subtitle: Text(online ? 'Online' : user.phone),

          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        );
      },
    );
  }
}
