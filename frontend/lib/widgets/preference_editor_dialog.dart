import "package:flutter/material.dart";

import "../utils/theme.dart";
import "travel_preference_selector.dart";

Future<bool> showPreferenceEditor(
  BuildContext context, {
  required Set<String> initialPreferences,
  required Future<void> Function(List<String> preferences) onSave,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final selected = {...initialPreferences};
      var saving = false;
      String? error;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              "Tune your travel signals",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: AppTheme.displayFontFamily,
                  ),
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.58,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TravelPreferenceSelector(
                      selected: selected,
                      enabled: !saving,
                      title: "Keep the good signals",
                      subtitle:
                          "Your choices shape the order of your recommendations.",
                      onToggle: (preference) {
                        setDialogState(() {
                          if (selected.contains(preference)) {
                            selected.remove(preference);
                          } else {
                            selected.add(preference);
                          }
                        });
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
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
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text("Cancel"),
              ),
              ElevatedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await onSave(selected.toList());
                          if (context.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setDialogState(() {
                              saving = false;
                              error =
                                  e.toString().replaceFirst("Exception: ", "");
                            });
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(saving ? "Saving…" : "Save signals"),
              ),
            ],
          );
        },
      );
    },
  );
  return result == true;
}
