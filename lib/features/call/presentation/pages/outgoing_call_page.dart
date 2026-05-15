import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer' as developer;

import '../../bloc/call_bloc.dart';
import '../../bloc/call_event.dart';
import '../../bloc/call_state.dart';
import '../../models/call_model.dart';
import '../widgets/call_control_button.dart';
import '../widgets/call_timer.dart';

final _logger = developer.log;

class OutgoingCallPage extends StatefulWidget {
  final String callId;
  final String remoteUid;
  final String remoteName;
  final String remotePhoto;
  final CallType callType;

  const OutgoingCallPage({
    super.key,
    required this.callId,
    required this.remoteUid,
    required this.remoteName,
    required this.remotePhoto,
    required this.callType,
  });

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  // FIX 1: await both renderers before use
  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  // FIX 2: wrap srcObject assignments in setState so Flutter rebuilds
  void _bindStreams(CallState state) {
    _logger(
      '📺 [UI] Binding streams | state=${state.runtimeType}',
      name: 'OutgoingCallPage.Streams',
    );
    // FIX 4: null-guard every stream before assigning
    setState(() {
      if (state is CallOutgoing && state.localStream != null) {
        _logger(
          '📺 [UI] Binding local stream (CallOutgoing)',
          name: 'OutgoingCallPage.Streams',
        );
        _localRenderer.srcObject = state.localStream;
      } else if (state is CallConnecting && state.localStream != null) {
        _logger(
          '📺 [UI] Binding local stream (CallConnecting)',
          name: 'OutgoingCallPage.Streams',
        );
        _localRenderer.srcObject = state.localStream;
      } else if (state is CallActive) {
        _logger(
          '📺 [UI] Binding streams (CallActive)',
          name: 'OutgoingCallPage.Streams',
        );
        _localRenderer.srcObject = state.localStream;
        if (state.remoteStream != null) {
          _remoteRenderer.srcObject = state.remoteStream;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallBloc, CallState>(
      listener: (context, state) {
        if (state is CallOutgoing ||
            state is CallConnecting ||
            state is CallActive) {
          _bindStreams(state);
        }
        if (state is CallEnded || state is CallFailed) {
          final reason = state is CallEnded
              ? (state).reason
              : (state as CallFailed).reason;
          _showEndedAndPop(context, reason);
        }
      },
      builder: (context, state) {
        final isVideo = widget.callType == CallType.video;
        final isActive = state is CallActive;
        // FIX 3: explicit cast — (state).remoteStream does not exist on CallState
        final remoteStream = isActive ? (state).remoteStream : null;
        final hasLocalStream =
            state is CallOutgoing ||
            state is CallConnecting ||
            state is CallActive;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background gradient (matches IncomingCallPage) ──
              if (isVideo && isActive && remoteStream != null)
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else if (isVideo && hasLocalStream)
                RTCVideoView(
                  _localRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true,
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.deepPurple.shade900, Colors.black],
                    ),
                  ),
                ),

              // ── Local PiP (video only, when active with remote stream) ──
              if (isVideo && isActive && remoteStream != null)
                Positioned(
                  top: 60,
                  right: 16,
                  width: 100,
                  height: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RTCVideoView(_localRenderer, mirror: true),
                  ),
                ),

              // ── Main content ──
              SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ── Caller info (top section, mirrors IncomingCallPage) ──
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          // Hide avatar when showing full-screen local video
                          if (!(isVideo && hasLocalStream && !isActive) &&
                              !(isVideo && isActive && remoteStream != null))
                            CircleAvatar(
                              radius: 70,
                              backgroundImage: widget.remotePhoto.isNotEmpty
                                  ? NetworkImage(widget.remotePhoto)
                                  : null,
                              child: widget.remotePhoto.isEmpty
                                  ? Text(
                                      widget.remoteName.isNotEmpty
                                          ? widget.remoteName[0].toUpperCase()
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
                            widget.remoteName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (isActive)
                            CallTimer(elapsed: (state).elapsed)
                          else if (state is CallReconnecting)
                            const Text(
                              'Reconnecting…',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 16,
                              ),
                            )
                          else
                            Text(
                              widget.callType == CallType.video
                                  ? 'Calling video…'
                                  : 'Calling audio…',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 16,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Icon(
                            widget.callType == CallType.video
                                ? Icons.videocam
                                : Icons.call,
                            color: Colors.white38,
                            size: 32,
                          ),
                        ],
                      ),
                    ),

                    // ── Controls (bottom section) ──
                    Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: _CallControls(
                        callId: widget.callId,
                        isVideo: isVideo,
                        isActive: isActive,
                        state: state,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEndedAndPop(BuildContext context, String reason) {
    final messages = {
      'hungUp': 'Call ended',
      'declined': 'Call declined',
      'missed': 'No answer',
      'failed': 'Call failed',
      'iceFailure': 'Connection failed',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(messages[reason] ?? 'Call ended')));
    if (context.canPop()) {
      context.pop();
    } else {
      Navigator.of(context).pop();
    }
  }
}

class _CallControls extends StatelessWidget {
  final String callId;
  final bool isVideo;
  final bool isActive;
  final CallState state;

  const _CallControls({
    required this.callId,
    required this.isVideo,
    required this.isActive,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CallBloc>();
    // FIX 3: explicit cast before accessing CallActive fields
    final micOn = state is CallActive ? (state as CallActive).micEnabled : true;
    final camOn = state is CallActive
        ? (state as CallActive).cameraEnabled
        : true;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (isActive) ...[
          CallControlButton(
            icon: micOn ? Icons.mic : Icons.mic_off,
            label: micOn ? 'Mute' : 'Unmute',
            size: 72,
            onTap: () => bloc.add(ToggleMicEvent(!micOn)),
          ),
          if (isVideo)
            CallControlButton(
              icon: camOn ? Icons.videocam : Icons.videocam_off,
              label: camOn ? 'Cam off' : 'Cam on',
              size: 72,
              onTap: () => bloc.add(ToggleCameraEvent(!camOn)),
            ),
          if (isVideo)
            CallControlButton(
              icon: Icons.flip_camera_ios,
              label: 'Flip',
              size: 72,
              onTap: () => bloc.add(SwitchCameraEvent()),
            ),
        ],
        CallControlButton(
          icon: Icons.call_end,
          label: 'End',
          color: Colors.red,
          size: 72,
          onTap: () => bloc.add(EndCallEvent(callId)),
        ),
      ],
    );
  }
}
