import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../providers/auth_provider.dart";
import "../utils/theme.dart";

Future<String?> showShareItineraryDialog(
  BuildContext context, {
  required String itineraryId,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      var submitting = false;
      String? error;

      return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            "Share this trip",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: AppTheme.displayFontFamily,
                ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Invite another GlobeTrotter to follow this route.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                enabled: !submitting,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "Username to share with",
                  hintText: "traveller_name",
                  prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              onPressed: submitting
                  ? null
                  : () async {
                      final username = controller.text.trim();
                      if (username.isEmpty) {
                        setDialogState(
                          () => error = "Enter a username to share with.",
                        );
                        return;
                      }

                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await context.read<AuthProvider>().shareItinerary(
                              itineraryId: itineraryId,
                              sharedWith: username,
                            );
                        if (context.mounted) {
                          Navigator.pop(context, username);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setDialogState(() {
                            submitting = false;
                            error = e.toString().replaceFirst(
                                  "Exception: ",
                                  "",
                                );
                          });
                        }
                      }
                    },
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 17),
              label: Text(submitting ? "Sharing…" : "Share"),
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  return result;
}
