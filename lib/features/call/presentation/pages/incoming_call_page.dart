import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/call_bloc.dart';
import '../../bloc/call_event.dart';
import '../../bloc/call_state.dart';
import '../../models/call_model.dart';
import '../widgets/call_control_button.dart';

class IncomingCallPage extends StatelessWidget {
  final CallModel call;
  final String callerName;
  final String callerPhoto;

  const IncomingCallPage({
    super.key,
    required this.call,
    required this.callerName,
    required this.callerPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<CallBloc, CallState>(
      listener: (context, state) {
        // After accepting, the Bloc transitions to Connecting/Active.
        // Navigate to the outgoing page which handles both roles.
        if (state is CallConnecting) {
          context.pushReplacement(
            '/active-call',
            extra: {
              'callId': call.callId,
              'remoteUid': call.callerId,
              'callType': call.type,
            },
          );
        }
        if (state is CallEnded || state is CallFailed) {
          if (context.canPop()) context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.deepPurple.shade900, Colors.black],
                ),
              ),
            ),

            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── Caller info ──
                  Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 70,
                          backgroundImage: callerPhoto.isNotEmpty
                              ? NetworkImage(callerPhoto)
                              : null,
                          child: callerPhoto.isEmpty
                              ? Text(
                                  callerName.isNotEmpty
                                      ? callerName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 52,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          callerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          call.isVideo
                              ? 'Incoming video call…'
                              : 'Incoming audio call…',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Icon(
                          call.isVideo ? Icons.videocam : Icons.call,
                          color: Colors.white38,
                          size: 32,
                        ),
                      ],
                    ),
                  ),

                  // ── Accept / Decline ──
                  Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CallControlButton(
                              icon: Icons.call_end,
                              label: 'Decline',
                              color: Colors.red,
                              size: 72,
                              onTap: () {
                                context.read<CallBloc>().add(
                                  DeclineCallEvent(call.callId),
                                );
                                if (context.canPop()) context.pop();
                              },
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CallControlButton(
                              icon: call.isVideo ? Icons.videocam : Icons.call,
                              label: 'Accept',
                              color: Colors.green,
                              size: 72,
                              onTap: () {
                                context.read<CallBloc>().add(
                                  AcceptCallEvent(call),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
