import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:globetrotter/widgets/account_dialogs.dart";

/// Opens [open] from a button, so the dialog runs on a real route with a real
/// exit animation. That matters: the defect these tests cover only appears
/// while the dialog is animating out, which never happens if the widget is
/// pumped directly.
Future<void> _openFrom(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => open(context),
            child: const Text("open"),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

void main() {
  group("Dialogs survive being closed", () {
    // The controllers used to be created beside showDialog and disposed on the
    // line after it returned. showDialog returns when the route is popped, not
    // when it has finished leaving, so the dialog kept rebuilding through its
    // exit animation and reached controllers that were already disposed.
    //
    // Every test here settles the animation after the dialog closes. Without
    // that the frames that actually throw are never pumped and the test would
    // pass against the broken code.

    testWidgets("changing a username", (tester) async {
      await _openFrom(
        tester,
        (context) => showUsernameChangeDialog(
          context,
          currentUsername: "amina",
          onSave: (_) async {},
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, "amina_travels");
      await tester.enterText(find.byType(TextFormField).last, "hunter2hunter");
      await tester.tap(find.widgetWithText(ElevatedButton, "Change username"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets("changing a password", (tester) async {
      await _openFrom(
        tester,
        (context) => showPasswordChangeDialog(
          context,
          onSave: (_) async {},
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), "oldpassword1");
      await tester.enterText(fields.at(1), "newpassword1");
      await tester.enterText(fields.at(2), "newpassword1");
      await tester.tap(find.widgetWithText(ElevatedButton, "Change password"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets("deleting an account", (tester) async {
      await _openFrom(tester, (context) => showDeleteAccountDialog(context));

      await tester.enterText(find.byType(TextFormField), "hunter2hunter");
      await tester.tap(find.text("Delete permanently"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets("dismissing without submitting", (tester) async {
      // Cancelling is the most common way out of these dialogs and hits the
      // same teardown path.
      await _openFrom(
        tester,
        (context) => showUsernameChangeDialog(
          context,
          currentUsername: "amina",
          onSave: (_) async {},
        ),
      );

      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group("A save that fails", () {
    testWidgets("keeps the dialog open and shows why", (tester) async {
      // The failure path rebuilds the dialog after an await, which is the
      // other half of the same lifetime problem: the state being written to
      // has to still exist.
      await _openFrom(
        tester,
        (context) => showUsernameChangeDialog(
          context,
          currentUsername: "amina",
          onSave: (_) async => throw Exception("That username is taken."),
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, "amina_travels");
      await tester.enterText(find.byType(TextFormField).last, "hunter2hunter");
      await tester.tap(find.widgetWithText(ElevatedButton, "Change username"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text("That username is taken."), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: "a failed save must not close the dialog and lose what was "
              "typed");
    });

    testWidgets("can be closed afterwards without throwing", (tester) async {
      await _openFrom(
        tester,
        (context) => showPasswordChangeDialog(
          context,
          onSave: (_) async => throw Exception("Wrong password."),
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), "wrongpassword");
      await tester.enterText(fields.at(1), "newpassword1");
      await tester.enterText(fields.at(2), "newpassword1");
      await tester.tap(find.widgetWithText(ElevatedButton, "Change password"));
      await tester.pumpAndSettle();
      expect(find.text("Wrong password."), findsOneWidget);

      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group("Button labels", () {
    testWidgets("are not mojibake", (tester) async {
      // These strings were stored as UTF-8 ellipses that had been decoded as
      // CP1252 somewhere upstream, so the buttons rendered a literal
      // "Updatingâ€¦" to users. Nothing in the app would ever have complained
      // about it, which is why it survived.
      await _openFrom(
        tester,
        (context) => showUsernameChangeDialog(
          context,
          currentUsername: "amina",
          onSave: (_) async {},
        ),
      );

      for (final widget in tester.widgetList<Text>(find.byType(Text))) {
        final text = widget.data ?? "";
        expect(
          text.contains("â€"),
          isFalse,
          reason: "mojibake in a user-visible label: $text",
        );
      }
    });
  });
}
