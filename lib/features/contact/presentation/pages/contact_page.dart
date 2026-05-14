// lib/features/contacts/presentation/pages/contacts_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:privtalk/features/contact/presentation/pages/widgets/contacts_view.dart';
import '../../../../core/services/permission_service.dart';
import '../../bloc/users_bloc.dart';
import '../../bloc/users_event.dart';
import '../../repository/users_repository.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePermissions());
  }

  Future<void> _handlePermissions() async {
    if (await PermissionService.hasCameraAndMicPermission()) return;

    final granted = await PermissionService.requestCameraAndMic();
    if (granted) return;

    if (!mounted) return;

    final permanentlyDenied = await PermissionService.isPermanentlyDenied();
    if (!mounted) return;

    permanentlyDenied ? _showSettingsDialog() : _showDeniedDialog();
  }

  void _showDeniedDialog() => showDialog(
    context: context,
    builder: (_) => const _PermissionDialog(
      title: 'Permission Denied',
      message: 'Camera and microphone permissions are required for calling.',
      actionLabel: 'OK',
    ),
  );

  void _showSettingsDialog() => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PermissionDialog(
      title: 'Permission Required',
      message:
          'Please enable permissions from Settings to use calling features.',
      actionLabel: 'Open Settings',
      onAction: () async {
        Navigator.pop(context);
        await PermissionService.openSettings();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => UsersBloc(UsersRepository())..add(FetchUsers()),
      child: ContactsView(onProfileTap: () => context.push('/profile')),
    );
  }
}

// Private dialog — lives in this file since it's page-level chrome, not reusable UI
class _PermissionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  const _PermissionDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: onAction ?? () => Navigator.pop(context),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
