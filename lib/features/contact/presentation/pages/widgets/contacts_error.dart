// lib/features/contacts/presentation/widgets/contacts_error.dart
import 'package:flutter/material.dart';

class ContactsError extends StatelessWidget {
  final String message;

  const ContactsError({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
