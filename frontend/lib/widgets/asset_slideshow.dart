import "dart:async";

import "package:flutter/material.dart";

import "../utils/theme.dart";

class AssetSlideshow extends StatefulWidget {
  final List<String> assetPaths;
  final Duration frameInterval;
  final Duration transitionDuration;
  final BoxFit fit;
  final double opacity;

  const AssetSlideshow({
    super.key,
    required this.assetPaths,
    this.frameInterval = const Duration(seconds: 6),
    this.transitionDuration = const Duration(milliseconds: 1000),
    this.fit = BoxFit.cover,
    this.opacity = 1,
  });

  @override
  State<AssetSlideshow> createState() => _AssetSlideshowState();
}

class _AssetSlideshowState extends State<AssetSlideshow>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant AssetSlideshow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPaths != widget.assetPaths ||
        oldWidget.frameInterval != widget.frameInterval) {
      _currentIndex = 0;
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    if (widget.assetPaths.length < 2) return;

    _timer = Timer.periodic(widget.frameInterval, (_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.assetPaths.length;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assetPaths.isEmpty) return _fallback;

    final path = widget.assetPaths[_currentIndex % widget.assetPaths.length];
    return Opacity(
      opacity: widget.opacity,
      child: AnimatedSwitcher(
        duration: widget.transitionDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: Image.asset(
          path,
          key: ValueKey(path),
          width: double.infinity,
          height: double.infinity,
          fit: widget.fit,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => _fallback,
        ),
      ),
    );
  }

  Widget get _fallback => const ColoredBox(color: AppTheme.primarySoft);
}
