import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as developer;
import 'package:privtalk/features/call/presentation/pages/outgoing_call_page.dart';

import '../../core/services/local_notification_service.dart';
import '../../features/call/bloc/call_bloc.dart';
import '../../features/call/bloc/call_event.dart';
import '../../features/call/models/call_model.dart';
import '../../features/call/repository/call_repository.dart';

final _logger = developer.log;

/// Drop this widget above MaterialApp.router in app.dart.
/// It listens for incoming calls and shows a full-screen overlay
/// (name + accept/reject) without navigating away from the current screen.
class IncomingCallListener extends StatefulWidget {
  final Widget child;

  const IncomingCallListener({super.key, required this.child});

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  final _repo = CallRepository();
  final Set<String> _shownCallIds = {};

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    if (_currentUid.isEmpty) return widget.child;

    return StreamBuilder<QuerySnapshot>(
      stream: _repo.watchIncomingCalls(_currentUid),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _logger(
            '📱 [LISTENER] Checking for incoming calls | docs=${snapshot.data!.docs.length}',
            name: 'IncomingCallListener',
          );
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final callId = data['callId'] as String? ?? doc.id;

            if (!_shownCallIds.contains(callId)) {
              _shownCallIds.add(callId);
              _logger(
                '📱 [LISTENER] New incoming call detected | callId=$callId | from=${data['callerId']}',
                name: 'IncomingCallListener',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _showIncomingCallOverlay(CallModel.fromMap(data));
              });
            }
          }
        }
        return widget.child;
      },
    );
  }

  Future<void> _showIncomingCallOverlay(CallModel call) async {
    _logger(
      '📱 [LISTENER] Showing incoming call overlay | callId=${call.callId} | from=${call.callerId} | isVideo=${call.isVideo}',
      name: 'IncomingCallListener',
    );

    if (call.callId == LocalNotificationService.pendingDeclineCallId) {
      LocalNotificationService.pendingDeclineCallId = null;
      _shownCallIds.remove(call.callId);
      context.read<CallBloc>().add(DeclineCallEvent(call.callId));
      return;
    }

    // Fetch caller info from Firestore users collection
    String callerName = 'Unknown';
    String callerPhoto = '';

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(call.callerId)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        callerName = data['name'] as String? ?? 'Unknown';
        callerPhoto = data['profileImage'] as String? ?? '';
        _logger(
          '📱 [LISTENER] Caller info fetched | name=$callerName',
          name: 'IncomingCallListener',
        );
      }
    } catch (e) {
      _logger(
        '⚠️ [LISTENER] Failed to fetch caller info: $e',
        name: 'IncomingCallListener',
      );
    }

    if (!mounted) return;

    if (call.callId == LocalNotificationService.pendingAnswerCallId) {
      LocalNotificationService.pendingAnswerCallId = null;
      _logger(
        '📱 [LISTENER] Auto-accepting from notification tap | callId=${call.callId}',
        name: 'IncomingCallListener',
      );
      _shownCallIds.remove(call.callId);
      context.read<CallBloc>().add(AcceptCallEvent(call));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: false).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => BlocProvider.value(
              value: context.read<CallBloc>(),
              child: _ActiveCallWrapper(
                call: call,
                callerName: callerName,
                callerPhoto: callerPhoto,
              ),
            ),
          ),
        );
      });
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => BlocProvider.value(
        value: context.read<CallBloc>(),
        child: _IncomingCallDialog(
          call: call,
          callerName: callerName,
          callerPhoto: callerPhoto,
          onDismiss: () => _shownCallIds.remove(call.callId),
        ),
      ),
    );
  }
}

class _IncomingCallDialog extends StatelessWidget {
  final CallModel call;
  final String callerName;
  final String callerPhoto;
  final VoidCallback onDismiss;

  const _IncomingCallDialog({
    required this.call,
    required this.callerName,
    required this.callerPhoto,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Pulsing avatar ──
            _PulsingAvatar(name: callerName, photoUrl: callerPhoto),
            const SizedBox(height: 20),

            // ── Name ──
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              call.isVideo ? 'Incoming video call' : 'Incoming audio call',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // ── Accept / Reject row ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject
                _CallDialogButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: Colors.red,
                  onTap: () {
                    context.read<CallBloc>().add(DeclineCallEvent(call.callId));
                    onDismiss();
                    Navigator.of(context).pop();
                  },
                ),

                // Accept
                _CallDialogButton(
                  icon: call.isVideo ? Icons.videocam : Icons.call,
                  label: 'Accept',
                  color: Colors.green,
                  onTap: () {
                    _logger(
                      '📱 [DIALOG] Call accepted | callId=${call.callId}',
                      name: 'IncomingCallListener',
                    );
                    Navigator.of(context).pop();
                    onDismiss();
                    // Accept the call in the Bloc
                    context.read<CallBloc>().add(AcceptCallEvent(call));
                    // Navigate to the active call page
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (context.mounted) {
                        Navigator.of(context, rootNavigator: false).push(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => BlocProvider.value(
                              value: context.read<CallBloc>(),
                              child: _ActiveCallWrapper(
                                call: call,
                                callerName: callerName,
                                callerPhoto: callerPhoto,
                              ),
                            ),
                          ),
                        );
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing ring animation around the avatar while ringing.
class _PulsingAvatar extends StatefulWidget {
  final String name;
  final String photoUrl;

  const _PulsingAvatar({required this.name, required this.photoUrl});

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.green.shade400, width: 3),
        ),
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 52,
          backgroundColor: Colors.deepPurple,
          backgroundImage: widget.photoUrl.isNotEmpty
              ? NetworkImage(widget.photoUrl)
              : null,
          child: widget.photoUrl.isEmpty
              ? Text(
                  widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 40, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }
}

class _CallDialogButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallDialogButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Wrapper so we can show OutgoingCallPage (which handles both roles)
/// after the receiver accepts.
class _ActiveCallWrapper extends StatelessWidget {
  final CallModel call;
  final String callerName;
  final String callerPhoto;

  const _ActiveCallWrapper({
    required this.call,
    required this.callerName,
    required this.callerPhoto,
  });

  @override
  Widget build(BuildContext context) {
    // Import your OutgoingCallPage — it handles the active state for both
    // caller and receiver since it just renders the CallBloc state.
    return OutgoingCallPage(
      callId: call.callId,
      remoteUid: call.callerId,
      remoteName: callerName,
      remotePhoto: callerPhoto,
      callType: call.type,
    );
  }
}

// Add this import at the top:
// import '../../features/call/presentation/pages/outgoing_call_page.dart';
