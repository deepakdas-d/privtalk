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
import 'package:privtalk/app/app_theme.dart';
import '../../chat/services/room_service.dart';
import '../../chat/services/message_service.dart';
import '../../chat/models/message_model.dart';
import '../../chat/presentation/widgets/message_bubble.dart';
import '../../chat/presentation/widgets/message_input.dart';

class UserAccessPage extends StatelessWidget {
  final String uid;

  const UserAccessPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    // Only provide UserAccessBloc here.
    // CallBloc is already provided by the ShellRoute in router.dart
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

class _UserAccessView extends StatefulWidget {
  final String uid;

  const _UserAccessView({required this.uid});

  @override
  State<_UserAccessView> createState() => _UserAccessViewState();
}

class _UserAccessViewState extends State<_UserAccessView> {
  final RoomService _roomService = RoomService();
  final MessageService _messageService = MessageService();

  String? _roomId;
  bool _isLoadingRoom = true;

  String get _currentUid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _initializeRoom();
  }

  Future<void> _initializeRoom() async {
    try {
      debugPrint('DEBUG UI: _initializeRoom started for currentUid=$_currentUid, remoteUid=${widget.uid}');
      final roomId = await _roomService.createOrGetRoom(_currentUid, widget.uid);
      debugPrint('DEBUG UI: _initializeRoom successfully got roomId=$roomId');
      if (mounted) {
        setState(() {
          _roomId = roomId;
          _isLoadingRoom = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('DEBUG UI: Error initializing room: $e');
      debugPrint('DEBUG UI: StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoadingRoom = false;
        });
      }
    }
  }

  void _startCall(
    BuildContext context,
    CallType type,
    String remoteName,
    String remotePhoto,
  ) {
    // Trigger the call in the Bloc
    context.read<CallBloc>().add(
      StartCallEvent(callerId: _currentUid, receiverId: widget.uid, callType: type),
    );

    // Navigate immediately — the page listens to Bloc state for the callId
    context.push(
      '/outgoing-call',
      extra: {
        'remoteUid': widget.uid,
        'remoteName': remoteName,
        'remotePhoto': remotePhoto,
        'callType': type,
      },
    );
  }

  void _sendMessage(String text) {
    if (_roomId != null) {
      _messageService.sendMessage(
        roomId: _roomId!,
        senderId: _currentUid,
        text: text,
      );
    }
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
      child: BlocBuilder<UserAccessBloc, UserAccessState>(
        builder: (context, state) {
          if (state is UserAccessLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (state is UserAccessError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: Center(child: Text(state.message)),
            );
          }

          if (state is UserAccessLoaded) {
            final user = state.user;

            return Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
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
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.call),
                    onPressed: () => _startCall(
                      context,
                      CallType.audio,
                      user.name,
                      user.photoUrl,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam),
                    onPressed: () => _startCall(
                      context,
                      CallType.video,
                      user.name,
                      user.photoUrl,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: _isLoadingRoom
                        ? const Center(child: CircularProgressIndicator())
                        : _roomId == null
                            ? const Center(child: Text('Failed to load chat room'))
                            : StreamBuilder<List<MessageModel>>(
                                stream: _messageService.getMessagesStream(_roomId!),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }

                                  if (snapshot.hasError) {
                                    return Center(child: Text('Error: ${snapshot.error}'));
                                  }

                                  final messages = snapshot.data ?? [];

                                  if (messages.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        'No messages yet. Say hi!',
                                        style: TextStyle(color: AppTheme.textSecondary),
                                      ),
                                    );
                                  }

                                  return ListView.builder(
                                    reverse: true, // Show newest at the bottom
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                      final message = messages[index];
                                      final isMe = message.senderId == _currentUid;
                                      return MessageBubble(message: message, isMe: isMe);
                                    },
                                  );
                                },
                              ),
                  ),
                  MessageInput(
                    onSend: _sendMessage,
                  ),
                ],
              ),
            );
          }

          return const Scaffold(body: SizedBox());
        },
      ),
    );
  }
}
