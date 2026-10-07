import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/widgets/looping_video.dart";
import "package:video_player/video_player.dart";

/// The sign-in screen shows a looping animation above the form.
///
/// It is an enhancement, not a requirement: browsers refuse autoplay, old
/// devices cannot decode H.264, and an asset can be dropped from a build.
/// Every one of those has to leave a usable sign-in form behind, never a
/// black rectangle or a hole where an animation was supposed to be.
class FakeController extends VideoPlayerController {
  final bool failOnInitialize;
  bool playing = false;
  bool looping = false;
  double volume = 1;
  int disposeCount = 0;

  FakeController({this.failOnInitialize = false})
      : super.networkUrl(Uri.parse("https://example.invalid/clip.mp4"));

  @override
  Future<void> initialize() async {
    if (failOnInitialize) {
      throw Exception("no decoder for this file");
    }
    value = const VideoPlayerValue(
      duration: Duration(seconds: 14),
      size: Size(576, 1024),
      isInitialized: true,
    );
  }

  @override
  Future<void> play() async {
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> setLooping(bool value) async {
    looping = value;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    super.dispose();
  }
}

const _fallbackKey = Key("fallback");

Future<FakeController?> pumpVideo(
  WidgetTester tester, {
  bool failOnInitialize = false,
  bool disableAnimations = false,
  VoidCallback? onUnavailable,
}) async {
  FakeController? made;

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LoopingVideo(
          assetPath: "assets/video/login_background.mp4",
          onUnavailable: onUnavailable,
          controllerFactory: (_) {
            made = FakeController(failOnInitialize: failOnInitialize);
            return made!;
          },
          child: const ColoredBox(
            color: Color(0xFF112233),
            child: SizedBox.expand(key: _fallbackKey),
          ),
        ),
      ),
    ),
  );

  // One frame for the fallback, one for the post-frame callback to run.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return made;
}

void main() {
  group("The sign-in animation", () {
    testWidgets("shows the fallback first, before any decoding happens",
        (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LoopingVideo(
              assetPath: "assets/video/login_background.mp4",
              controllerFactory: (_) => FakeController(),
              child: const SizedBox.expand(key: _fallbackKey),
            ),
          ),
        ),
      );

      // The very first frame, before the post-frame callback fires.
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets("plays muted and looping once it is ready", (tester) async {
      final controller = await pumpVideo(tester);

      expect(controller, isNotNull);
      expect(controller!.playing, isTrue);
      expect(controller.looping, isTrue,
          // A 14 second clip that stops dead leaves a frozen frame above
          // the form for as long as the user is typing.
          reason: "the animation has to loop");
      expect(controller.volume, 0,
          reason: "browsers gate autoplay on the muted flag, and nobody "
              "wants sound from a sign-in screen");
      expect(find.byType(VideoPlayer), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets("keeps the fallback underneath rather than replacing it",
        (tester) async {
      await pumpVideo(tester);

      // If the video is ever torn down or fails to paint a frame, there
      // must still be something behind it.
      expect(find.byKey(_fallbackKey), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets("keeps the fallback when the video cannot play",
        (tester) async {
      final controller = await pumpVideo(tester, failOnInitialize: true);

      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(controller!.disposeCount, 1,
          reason: "a controller that failed still holds platform resources");

      await tester.pumpAndSettle();
    });

    testWidgets("tells the caller when it will never play, so the space "
        "can be reclaimed", (tester) async {
      // Without this the login screen holds open a 200 pixel gap where an
      // animation was supposed to be.
      var notified = 0;
      await pumpVideo(tester,
          failOnInitialize: true, onUnavailable: () => notified += 1);

      expect(notified, 1);
      await tester.pumpAndSettle();
    });

    testWidgets("does not start the video when the user asked for less "
        "motion", (tester) async {
      // An endlessly looping clip is the thing "reduce motion" exists to
      // switch off.
      var notified = 0;
      await pumpVideo(tester,
          disableAnimations: true, onUnavailable: () => notified += 1);

      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(notified, 1,
          reason: "reduced motion should reclaim the space too");

      await tester.pumpAndSettle();
    });

    testWidgets("pauses when the app goes to the background", (tester) async {
      final controller = await pumpVideo(tester);
      expect(controller!.playing, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.playing, isFalse,
          reason: "decoding frames nobody can see drains the battery");

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.playing, isTrue);

      await tester.pumpAndSettle();
    });

    testWidgets("releases the player when the screen is left",
        (tester) async {
      final controller = await pumpVideo(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(controller!.disposeCount, greaterThan(0),
          reason: "signing in leaves this screen for good");
    });
  });
}
