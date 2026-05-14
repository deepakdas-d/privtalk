import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/call_bloc.dart';
import '../../bloc/call_event.dart';
import '../../bloc/call_state.dart';
import '../../models/call_model.dart';
import '../widgets/call_control_button.dart';
import '../widgets/call_timer.dart';

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
    _localRenderer.initialize();
    _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _bindStreams(CallActive state) {
    _localRenderer.srcObject = state.localStream;
    if (state.remoteStream != null) {
      _remoteRenderer.srcObject = state.remoteStream;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallBloc, CallState>(
      listener: (context, state) {
        if (state is CallActive) _bindStreams(state);

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

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Remote video / avatar background ──
              if (isActive && isVideo)
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                _AvatarBackground(
                  name: widget.remoteName,
                  photoUrl: widget.remotePhoto,
                ),

              // ── Local PiP (video only) ──
              if (isVideo && isActive)
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

              // ── Status / name overlay ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        widget.remoteName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (state is CallActive)
                        CallTimer(elapsed: state.elapsed)
                      else if (state is CallReconnecting)
                        const Text(
                          'Reconnecting…',
                          style: TextStyle(color: Colors.white70),
                        )
                      else
                        const Text(
                          'Calling…',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Controls ──
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: _CallControls(
                    callId: widget.callId,
                    isVideo: isVideo,
                    isActive: isActive,
                    state: state,
                  ),
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
    if (context.canPop()) context.pop();
  }
}

class _AvatarBackground extends StatelessWidget {
  final String name;
  final String photoUrl;

  const _AvatarBackground({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.deepPurple.shade900,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 64,
              backgroundImage: photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 48, color: Colors.white),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
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
    final micOn = state is CallActive ? (state as CallActive).micEnabled : true;
    final camOn = state is CallActive
        ? (state as CallActive).cameraEnabled
        : true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (isActive) ...[
            CallControlButton(
              icon: micOn ? Icons.mic : Icons.mic_off,
              label: micOn ? 'Mute' : 'Unmute',
              onTap: () => bloc.add(ToggleMicEvent(!micOn)),
            ),
            if (isVideo)
              CallControlButton(
                icon: camOn ? Icons.videocam : Icons.videocam_off,
                label: camOn ? 'Cam off' : 'Cam on',
                onTap: () => bloc.add(ToggleCameraEvent(!camOn)),
              ),
            if (isVideo)
              CallControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onTap: () => bloc.add(SwitchCameraEvent()),
              ),
          ],
          CallControlButton(
            icon: Icons.call_end,
            label: 'End',
            color: Colors.red,
            onTap: () => bloc.add(EndCallEvent(callId)),
          ),
        ],
      ),
    );
  }
}
