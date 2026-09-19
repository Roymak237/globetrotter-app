import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:provider/provider.dart";

import "../services/call_service.dart";
import "../utils/theme.dart";

/// The in-call screen, covering every stage from dialling to hang-up.
///
/// It closes itself when the call ends rather than waiting to be popped, so a
/// call that the other side drops does not leave a dead screen on top of the
/// conversation.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallService>(
      builder: (context, service, _) {
        final session = service.session;

        if (session == null || service.stage == CallStage.idle) {
          // Pop after this frame; tearing the route down mid-build is not safe.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }

        final showVideo = session.video && service.stage == CallStage.active;

        return PopScope(
          // Leaving with the back gesture would hide the call without ending
          // it, so the only way out is the hang-up button.
          canPop: false,
          child: Scaffold(
            backgroundColor: const Color(0xFF16100C),
            body: SafeArea(
              child: Stack(
                children: [
                  if (showVideo) _videoLayer(service),
                  if (!showVideo) _audioLayer(context, service, session),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 26,
                    child: _controls(context, service, session),
                  ),
                  if (showVideo)
                    Positioned(
                      top: 16,
                      right: 16,
                      width: 108,
                      height: 150,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: RTCVideoView(
                          service.localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _videoLayer(CallService service) {
    return Positioned.fill(
      child: RTCVideoView(
        service.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }

  Widget _audioLayer(
      BuildContext context, CallService service, CallSession session) {
    return Positioned.fill(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 58,
            backgroundColor: AppTheme.primaryDark,
            backgroundImage: session.peerAvatarUrl.isNotEmpty
                ? NetworkImage(session.peerAvatarUrl)
                : null,
            child: session.peerAvatarUrl.isEmpty
                ? Text(
                    session.title.isNotEmpty
                        ? session.title[0].toUpperCase()
                        : "?",
                    style: const TextStyle(
                      fontSize: 42,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 20),
          Text(
            session.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stageLabel(service, session),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (service.error != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                service.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.accent, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _stageLabel(CallService service, CallSession session) {
    switch (service.stage) {
      case CallStage.dialling:
        return "Calling...";
      case CallStage.ringing:
        return session.incoming ? "Incoming call" : "Ringing...";
      case CallStage.connecting:
        return "Connecting...";
      case CallStage.active:
        return session.video ? "Video call" : "Voice call";
      case CallStage.ended:
        return "Call ended";
      case CallStage.idle:
        return "";
    }
  }

  Widget _controls(
      BuildContext context, CallService service, CallSession session) {
    final ringingIncoming =
        session.incoming && service.stage == CallStage.ringing;

    if (ringingIncoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleButton(
            icon: Icons.call_end_rounded,
            colour: const Color(0xFFD1372B),
            tooltip: "Decline",
            onPressed: service.decline,
          ),
          _circleButton(
            icon: session.video ? Icons.videocam_rounded : Icons.call_rounded,
            colour: const Color(0xFF3F8A4B),
            tooltip: "Answer",
            onPressed: service.accept,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleButton(
          icon: service.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          colour: Colors.white24,
          tooltip: service.muted ? "Unmute" : "Mute",
          onPressed: service.toggleMute,
        ),
        const SizedBox(width: 14),
        if (session.video) ...[
          _circleButton(
            icon: service.cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            colour: Colors.white24,
            tooltip: service.cameraOff ? "Turn camera on" : "Turn camera off",
            onPressed: service.toggleCamera,
          ),
          const SizedBox(width: 14),
          _circleButton(
            icon: Icons.cameraswitch_rounded,
            colour: Colors.white24,
            tooltip: "Switch camera",
            onPressed: service.switchCamera,
          ),
          const SizedBox(width: 14),
        ] else ...[
          _circleButton(
            icon: service.speakerOn
                ? Icons.volume_up_rounded
                : Icons.hearing_rounded,
            colour: Colors.white24,
            tooltip: service.speakerOn ? "Use earpiece" : "Use speaker",
            onPressed: service.toggleSpeaker,
          ),
          const SizedBox(width: 14),
        ],
        _circleButton(
          icon: Icons.call_end_rounded,
          colour: const Color(0xFFD1372B),
          tooltip: "End call",
          onPressed: service.hangUp,
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color colour,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colour,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
