import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/providers/locale_provider.dart";
import "package:globetrotter/widgets/auth_widgets.dart";
import "package:globetrotter/widgets/looping_video.dart";
import "package:provider/provider.dart";

/// The animation belongs above the form, not behind it.
void main() {
  testWidgets("the sign-in backdrop carries no video behind the form",
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: const MaterialApp(
          home: AuthBackdrop(child: Text("form goes here")),
        ),
      ),
    );
    await tester.pump();

    // AuthBackdrop paints the scrim and the still slideshow. A video here
    // would be moving picture underneath the username and password fields.
    expect(find.byType(LoopingVideo), findsNothing);
    expect(find.text("form goes here"), findsOneWidget);
  });
}
