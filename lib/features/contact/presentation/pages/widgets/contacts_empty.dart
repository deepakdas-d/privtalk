// lib/features/contacts/presentation/widgets/contacts_empty.dart
import 'package:flutter/material.dart';

class ContactsEmpty extends StatelessWidget {
  const ContactsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('No contacts found', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
