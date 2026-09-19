import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/chat.dart';
import '../services/media_service.dart';
import '../utils/theme.dart';

/// Images always use authenticated bytes (also on Flutter web).
class ChatAttachmentView extends StatefulWidget {
  final ChatAttachment attachment;
  final String token;
  const ChatAttachmentView(
      {super.key, required this.attachment, required this.token});
  @override
  State<ChatAttachmentView> createState() => _ChatAttachmentViewState();
}

class _ChatAttachmentViewState extends State<ChatAttachmentView> {
  final _media = MediaService();
  Future<Uint8List>? _image;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  void _loadImage() {
    _image = widget.attachment.kind == 'image'
        ? _media.fetchBytes(widget.token, widget.attachment.url)
        : null;
  }

  @override
  void didUpdateWidget(covariant ChatAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.url != widget.attachment.url ||
        oldWidget.token != widget.token) _loadImage();
  }

  @override
  void dispose() {
    _media.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    final attachment = widget.attachment;
    setState(() => _busy = true);
    try {
      if (attachment.kind == 'image') {
        final bytes = await _image!;
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (_) => Dialog(
                  child: Stack(children: [
                    InteractiveViewer(child: Image.memory(bytes)),
                    Positioned(
                        right: 0,
                        top: 0,
                        child: CloseButton(
                            onPressed: () => Navigator.of(context).pop())),
                  ]),
                ));
      } else if (attachment.kind == 'audio' || attachment.kind == 'video') {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                ChatMediaPlayer(attachment: attachment, token: widget.token)));
      } else {
        final ticket =
            await _media.playbackTicket(widget.token, attachment.url);
        if (!mounted) return;
        // A second explicit tap avoids browser popup blockers after async auth.
        await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: Text(attachment.filename.isEmpty
                      ? 'Document'
                      : attachment.filename),
                  content: const Text(
                      'Open this file in your browser. This private link expires shortly.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () async {
                          try {
                            final opened = await launchUrl(ticket,
                                mode: LaunchMode.externalApplication,
                                webOnlyWindowName: '_blank');
                            if (!opened)
                              throw Exception('No app can open this document.');
                            if (dialogContext.mounted)
                              Navigator.pop(dialogContext);
                          } catch (error) {
                            if (mounted) _error(error);
                          }
                        },
                        child: const Text('Open PDF'))
                  ],
                ));
      }
    } catch (error) {
      if (mounted) _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    return Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _busy ? null : _open,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_image != null)
                    FutureBuilder<Uint8List>(
                        future: _image,
                        builder: (context, snapshot) {
                          if (snapshot.hasError)
                            return TextButton.icon(
                                onPressed: () => setState(_loadImage),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry image'));
                          if (!snapshot.hasData)
                            return const SizedBox(
                                height: 80,
                                child:
                                    Center(child: CircularProgressIndicator()));
                          return Image.memory(snapshot.data!,
                              height: 170,
                              width: 240,
                              fit: BoxFit.cover,
                              cacheWidth: 720,
                              errorBuilder: (_, __, ___) =>
                                  const Text('Image cannot be decoded'));
                        }),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        switch (a.kind) {
                          'image' => Icons.photo_outlined,
                          'video' => Icons.play_circle_outline,
                          'audio' => Icons.audiotrack,
                          _ => Icons.picture_as_pdf_outlined
                        },
                        color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(a.filename.isEmpty ? a.kind : a.filename,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(color: AppTheme.textPrimary))),
                    if (_busy)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ]),
                  Text(
                      '${(a.size / 1024).toStringAsFixed(0)} KB'
                      '${a.durationMs > 0 ? ' · ${(a.durationMs / 1000).round()}s' : ''}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ],
              )),
        ));
  }
}

/// Playback uses a scoped, expiring media ticket, not a bearer token in a URL.
class ChatMediaPlayer extends StatefulWidget {
  final ChatAttachment attachment;
  final String token;
  const ChatMediaPlayer(
      {super.key, required this.attachment, required this.token});
  @override
  State<ChatMediaPlayer> createState() => _ChatMediaPlayerState();
}

class _ChatMediaPlayerState extends State<ChatMediaPlayer> {
  final _media = MediaService();
  AudioPlayer? _audio;
  VideoPlayerController? _video;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  bool _loading = true;
  bool _playing = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri =
          await _media.playbackTicket(widget.token, widget.attachment.url);
      if (!mounted) return;
      if (widget.attachment.kind == 'video') {
        final video = VideoPlayerController.networkUrl(uri);
        _video = video;
        await video.initialize();
        if (!mounted) return;
        video.addListener(_videoChanged);
      } else {
        final audio = AudioPlayer();
        _audio = audio;
        _stateSub = audio.onPlayerStateChanged.listen((state) {
          if (mounted) setState(() => _playing = state == PlayerState.playing);
        });
        _positionSub = audio.onPositionChanged.listen((value) {
          if (mounted) setState(() => _position = value);
        });
        _durationSub = audio.onDurationChanged.listen((value) {
          if (mounted) setState(() => _duration = value);
        });
        await audio.setSource(UrlSource(uri.toString()));
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString();
          _loading = false;
        });
    }
  }

  void _videoChanged() {
    if (!mounted || _video == null) return;
    setState(() {
      _playing = _video!.value.isPlaying;
      _position = _video!.value.position;
      _duration = _video!.value.duration;
      if (_video!.value.hasError) _error = _video!.value.errorDescription;
    });
  }

  Future<void> _toggle() async {
    try {
      if (_video != null) {
        if (_position >= _duration) await _video!.seekTo(Duration.zero);
        _playing ? await _video!.pause() : await _video!.play();
      } else if (_audio != null) {
        if (_position >= _duration) await _audio!.seek(Duration.zero);
        _playing ? await _audio!.pause() : await _audio!.resume();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _media.dispose();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _video?.removeListener(_videoChanged);
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.attachment.filename),
            flexibleSpace: AppTheme.appBarBackground,
            foregroundColor: Colors.white),
        body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            '$_error\nClose and reopen to obtain a fresh media link.'))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            if (_video != null)
                              Flexible(
                                  child: AspectRatio(
                                      aspectRatio: _video!.value.aspectRatio,
                                      child: VideoPlayer(_video!)))
                            else
                              const Icon(Icons.graphic_eq,
                                  size: 96, color: AppTheme.primary),
                            Text(
                                '${_position.inSeconds}s / ${_duration.inSeconds}s'),
                            IconButton(
                                iconSize: 48,
                                onPressed: _toggle,
                                tooltip: _playing ? 'Pause' : 'Play',
                                icon: Icon(
                                    _playing
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    color: AppTheme.primary)),
                          ])),
      );
}

/// Bounded voice-note recorder. A stopped note is uploaded into the draft, not
/// sent automatically, allowing the traveller to review/remove it first.
class ChatVoiceRecorder extends StatefulWidget {
  final String token;
  final bool enabled;
  final ValueChanged<ChatAttachment> onRecorded;
  final ValueChanged<bool> onBusyChanged;
  const ChatVoiceRecorder(
      {super.key,
      required this.token,
      required this.enabled,
      required this.onRecorded,
      required this.onBusyChanged});
  @override
  State<ChatVoiceRecorder> createState() => _ChatVoiceRecorderState();
}

class _ChatVoiceRecorderState extends State<ChatVoiceRecorder> {
  final _recorder = AudioRecorder();
  final _media = MediaService();
  bool _recording = false;
  bool _busy = false;
  DateTime? _started;
  String? _path;
  Timer? _limit;

  Future<void> _start() async {
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      if (!await _recorder.hasPermission())
        throw Exception('Microphone permission is required.');
      if (!mounted) return;
      final path = await _media.recordingPath();
      if (!mounted) return;
      _path = path;
      await _recorder.start(
          RecordConfig(
              encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
              bitRate: 64000,
              sampleRate: 44100),
          path: path);
      if (!mounted) return;
      _started = DateTime.now();
      setState(() => _recording = true);
      _limit = Timer(const Duration(minutes: 2), () => _stop());
    } catch (error) {
      if (mounted) {
        _showError(error);
        widget.onBusyChanged(false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({bool cancel = false}) async {
    if (_busy) return;
    _limit?.cancel();
    setState(() => _busy = true);
    String? path;
    try {
      final duration = DateTime.now().difference(_started!).inMilliseconds;
      path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      if (!cancel && mounted && path != null) {
        final bytes = await _media.readRecording(path);
        if (!mounted) return;
        final attachment = await _media.upload(
            widget.token,
            bytes,
            kIsWeb ? 'voice-note.webm' : 'voice-note.m4a',
            kIsWeb ? 'audio/webm' : 'audio/mp4',
            durationMs: duration);
        if (mounted) widget.onRecorded(attachment);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (path != null) {
        try {
          await _media.removeRecording(path);
        } catch (_) {/* best effort temp cleanup */}
      }
      _path = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _recording = false;
        });
        widget.onBusyChanged(false);
      }
    }
  }

  void _showError(Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
  Future<void> _cleanup() async {
    try {
      await _recorder.cancel();
    } catch (_) {/* already stopped */}
    await _recorder.dispose();
    final path = _path;
    if (path != null && !kIsWeb) {
      try {
        await _media.removeRecording(path);
      } catch (_) {/* already removed */}
    }
  }

  @override
  void dispose() {
    _limit?.cancel();
    _media.dispose();
    unawaited(_cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (_recording)
          IconButton(
              tooltip: 'Discard recording',
              onPressed: _busy ? null : () => _stop(cancel: true),
              icon: const Icon(Icons.close)),
        IconButton(
            tooltip: _recording
                ? 'Stop recording (2 min maximum)'
                : 'Record voice note',
            onPressed: _busy
                ? null
                : _recording
                    ? () => _stop()
                    : widget.enabled
                        ? _start
                        : null,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_recording ? Icons.stop_circle : Icons.mic_none,
                    color: _recording ? AppTheme.error : AppTheme.primary)),
      ]);
}
