import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../datasource/ice_datasource.dart';

/// Owns the RTCPeerConnection and local/remote media.
/// Callers listen to [onIceCandidate], [onConnectionStateChange],
/// [onRemoteStream], and [onRenegotiationNeeded].
class WebRtcService {
  final IceDatasource _iceDatasource;

  WebRtcService({IceDatasource? iceDatasource})
    : _iceDatasource = iceDatasource ?? IceDatasource();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Callbacks wired up by CallBloc
  void Function(RTCIceCandidate)? onIceCandidate;
  void Function(RTCPeerConnectionState)? onConnectionStateChange;
  void Function(MediaStream)? onRemoteStream;
  void Function()? onRenegotiationNeeded;

  RTCPeerConnection? get pc => _pc;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> initialize({required bool isVideo}) async {
    final iceServers = await _iceDatasource.fetchIceServers();

    final config = {
      'iceServers': iceServers,
      'iceCandidatePoolSize': 10,
      'sdpSemantics': 'unified-plan',
    };

    _pc = await createPeerConnection(config);
    _localStream = await _getLocalStream(isVideo: isVideo);

    // Add tracks (unified-plan)
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _wireCallbacks();
  }

  Future<MediaStream> _getLocalStream({required bool isVideo}) async {
    final constraints = {
      'audio': true,
      'video': isVideo
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  void _wireCallbacks() {
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) onIceCandidate?.call(candidate);
    };

    _pc!.onConnectionState = (state) {
      onConnectionStateChange?.call(state);
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _pc!.onRenegotiationNeeded = () => onRenegotiationNeeded?.call();
  }

  // ── Offer / Answer ────────────────────────────────────────────────────────

  Future<RTCSessionDescription> createOffer() async {
    final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {
    final desc = RTCSessionDescription(
      sdpMap['sdp'] as String,
      sdpMap['type'] as String,
    );
    await _pc!.setRemoteDescription(desc);
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> candidateMap) async {
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String,
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    );
    await _pc!.addCandidate(candidate);
  }

  // ── Camera / Mic toggles ─────────────────────────────────────────────────

  void toggleMic({required bool enabled}) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = enabled);
  }

  void toggleCamera({required bool enabled}) {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = enabled);
  }

  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _pc?.close();
    _pc = null;
    _localStream = null;
    _remoteStream = null;
  }
}
