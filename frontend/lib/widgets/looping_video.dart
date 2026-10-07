import "package:flutter/material.dart";
import "package:video_player/video_player.dart";

/// Builds the controller for a backdrop video.
///
/// Swapped out in tests, where there is no video platform to talk to and a
/// real controller would hang on `initialize()`.
typedef VideoControllerFactory = VideoPlayerController Function(String asset);

VideoPlayerController _defaultFactory(String asset) =>
    VideoPlayerController.asset(asset);

/// Plays a short looping video, falling back to [child].
///
/// The video is an enhancement, never a requirement. [child] is shown
/// immediately and stays on screen until the video is genuinely ready, so a
/// device that cannot decode it, a browser that blocks autoplay, or a
/// missing asset all degrade to whatever was already there rather than to a
/// black rectangle.
class LoopingVideo extends StatefulWidget {
  final String assetPath;
  final Widget child;
  final double opacity;
  final Duration fadeDuration;

  /// How the frame fills the space it is given.
  ///
  /// [BoxFit.contain] keeps the whole frame visible, which matters when the
  /// clip is a composed animation rather than footage: cropping it would
  /// cut off whatever it was drawn around.
  final BoxFit fit;

  /// Called once when the video will never play.
  ///
  /// A caller that reserved space for the clip can collapse it instead of
  /// leaving a gap where an animation was supposed to be.
  final VoidCallback? onUnavailable;

  /// Injection seam for tests. Production never passes this.
  @visibleForTesting
  final VideoControllerFactory? controllerFactory;

  const LoopingVideo({
    super.key,
    required this.assetPath,
    required this.child,
    this.opacity = 1,
    this.fadeDuration = const Duration(milliseconds: 900),
    this.fit = BoxFit.cover,
    this.onUnavailable,
    this.controllerFactory,
  });

  @override
  State<LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<LoopingVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;

  /// Set once the video has failed. Nothing retries after this: a second
  /// attempt would fail the same way and the fallback is already correct.
  bool _failed = false;

  /// Records the failure and lets the caller reclaim the space.
  void _giveUp() {
    if (_failed) return;
    setState(() => _failed = true);
    widget.onUnavailable?.call();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred so the first frame paints the fallback rather than waiting
    // on a decoder, and so MediaQuery is available to read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _failed || _controller != null) return;

    // An endlessly looping video is exactly what "reduce motion" is meant
    // to suppress, and the fallback is already a still image.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _giveUp();
      return;
    }

    final factory = widget.controllerFactory ?? _defaultFactory;
    final controller = factory(widget.assetPath);
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      // The file carries no audio track, but browsers gate autoplay on the
      // muted flag rather than on the absence of sound.
      await controller.setVolume(0);
      await controller.play();
      setState(() => _ready = true);
    } catch (_) {
      // Codec unsupported, asset missing, autoplay refused: all of these
      // mean "keep the fallback", and none is worth interrupting a
      // sign-in to report.
      await controller.dispose();
      if (!mounted) return;
      _controller = null;
      _giveUp();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (state == AppLifecycleState.resumed) {
      controller.play();
    } else {
      // Decoding frames nobody can see drains the battery of a phone left
      // sitting on the sign-in screen.
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_ready && controller != null)
          AnimatedOpacity(
            opacity: widget.opacity,
            duration: widget.fadeDuration,
            curve: Curves.easeOut,
            child: FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
      ],
    );
  }
}
