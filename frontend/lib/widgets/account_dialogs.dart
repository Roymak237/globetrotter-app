import "package:flutter/material.dart";

import "../models/user.dart";
import "../utils/regions.dart";
import "../utils/theme.dart";

class UsernameChangeInput {
  final String username;
  final String currentPassword;

  const UsernameChangeInput({
    required this.username,
    required this.currentPassword,
  });
}

class PasswordChangeInput {
  final String currentPassword;
  final String newPassword;

  const PasswordChangeInput({
    required this.currentPassword,
    required this.newPassword,
  });
}

Future<bool> showAccountDetailsEditor(
  BuildContext context, {
  required User user,
  required Future<void> Function(
    String displayName,
    String email,
    String homeRegion,
    String avatarUrl,
  ) onSave,
}) async {
  final formKey = GlobalKey<FormState>();
  final displayNameController = TextEditingController(text: user.displayName);
  final emailController = TextEditingController(text: user.email);
  final avatarController = TextEditingController(text: user.avatarUrl);
  var selectedRegion = user.homeRegion.isEmpty ? null : user.homeRegion;
  var saving = false;
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          "Edit profile details",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: AppTheme.displayFontFamily,
              ),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.64,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: displayNameController,
                    enabled: !saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Display name",
                      hintText: "How should we greet you?",
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) => value != null && value.length > 160
                        ? "Use 160 characters or fewer"
                        : null,
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: emailController,
                    enabled: !saving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: "Email (optional)",
                      hintText: "you@example.com",
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? "";
                      if (email.isNotEmpty &&
                          !RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
                              .hasMatch(email)) {
                        return "Enter a valid email address";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 13),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRegion,
                    decoration: const InputDecoration(
                      labelText: "Home region (optional)",
                      prefixIcon: Icon(Icons.home_work_outlined),
                    ),
                    items: cameroonRegions
                        .map(
                          (region) => DropdownMenuItem(
                            value: region,
                            child: Text(region),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(
                              () => selectedRegion = value,
                            ),
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: avatarController,
                    enabled: !saving,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: "Avatar URL (optional)",
                      hintText: "https://…",
                      prefixIcon: Icon(Icons.image_outlined),
                      helperText:
                          "Use a public image URL, or leave blank for initials",
                    ),
                    validator: (value) {
                      final avatar = value?.trim() ?? "";
                      if (avatar.isEmpty) return null;
                      final uri = Uri.tryParse(avatar);
                      if (uri == null ||
                          !["http", "https"].contains(uri.scheme)) {
                        return "Use a valid http or https URL";
                      }
                      return null;
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
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setDialogState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await onSave(
                        displayNameController.text.trim(),
                        emailController.text.trim(),
                        selectedRegion ?? "",
                        avatarController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString().replaceFirst("Exception: ", "");
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
            label: Text(saving ? "Saving…" : "Save profile"),
          ),
        ],
      ),
    ),
  );
  displayNameController.dispose();
  emailController.dispose();
  avatarController.dispose();
  return result == true;
}

Future<bool> showUsernameChangeDialog(
  BuildContext context, {
  required String currentUsername,
  required Future<void> Function(UsernameChangeInput input) onSave,
}) async {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController(text: currentUsername);
  final passwordController = TextEditingController();
  var obscurePassword = true;
  var saving = false;
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text("Change username"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: usernameController,
                enabled: !saving,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: "New username",
                  hintText: "traveller_name",
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) {
                  final username = value?.trim().toLowerCase() ?? "";
                  if (!RegExp(r"^[a-z0-9_]{3,30}$").hasMatch(username)) {
                    return "Use 3–30 lowercase letters, numbers, or _";
                  }
                  if (username == currentUsername) {
                    return "Choose a different username";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: passwordController,
                enabled: !saving,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: "Current password",
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip:
                        obscurePassword ? "Show password" : "Hide password",
                    onPressed: () => setDialogState(
                      () => obscurePassword = !obscurePassword,
                    ),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? "Enter your current password"
                    : null,
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
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: saving
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setDialogState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await onSave(
                        UsernameChangeInput(
                          username:
                              usernameController.text.trim().toLowerCase(),
                          currentPassword: passwordController.text,
                        ),
                      );
                      if (context.mounted) Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (context.mounted) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString().replaceFirst("Exception: ", "");
                        });
                      }
                    }
                  },
            child: Text(saving ? "Updating…" : "Change username"),
          ),
        ],
      ),
    ),
  );
  usernameController.dispose();
  passwordController.dispose();
  return result == true;
}

Future<bool> showPasswordChangeDialog(
  BuildContext context, {
  required Future<void> Function(PasswordChangeInput input) onSave,
}) async {
  final formKey = GlobalKey<FormState>();
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  var obscureCurrent = true;
  var obscureNew = true;
  var saving = false;
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text("Change password"),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PasswordField(
                  controller: currentController,
                  label: "Current password",
                  obscureText: obscureCurrent,
                  enabled: !saving,
                  onToggle: () => setDialogState(
                    () => obscureCurrent = !obscureCurrent,
                  ),
                ),
                const SizedBox(height: 13),
                _PasswordField(
                  controller: newController,
                  label: "New password",
                  helperText: "At least 8 characters",
                  obscureText: obscureNew,
                  enabled: !saving,
                  onToggle: () => setDialogState(
                    () => obscureNew = !obscureNew,
                  ),
                  validator: (value) => value == null || value.length < 8
                      ? "Use at least 8 characters"
                      : null,
                ),
                const SizedBox(height: 13),
                TextFormField(
                  controller: confirmController,
                  enabled: !saving,
                  obscureText: obscureNew,
                  decoration: const InputDecoration(
                    labelText: "Confirm new password",
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                  validator: (value) => value != newController.text
                      ? "Passwords do not match"
                      : null,
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
          ElevatedButton(
            onPressed: saving
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setDialogState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await onSave(
                        PasswordChangeInput(
                          currentPassword: currentController.text,
                          newPassword: newController.text,
                        ),
                      );
                      if (context.mounted) Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (context.mounted) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString().replaceFirst("Exception: ", "");
                        });
                      }
                    }
                  },
            child: Text(saving ? "Updating…" : "Change password"),
          ),
        ],
      ),
    ),
  );
  currentController.dispose();
  newController.dispose();
  confirmController.dispose();
  return result == true;
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool obscureText;
  final bool enabled;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.enabled,
    required this.onToggle,
    this.helperText,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: obscureText ? "Show password" : "Hide password",
          onPressed: onToggle,
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: validator ??
          (value) => value == null || value.isEmpty
              ? "Enter your current password"
              : null,
    );
  }
}

Future<bool> showConfirmAccountAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary)
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

Future<String?> showDeleteAccountDialog(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  final passwordController = TextEditingController();
  var obscurePassword = true;

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Delete your account?"),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "This permanently removes your profile, itineraries, and shares. This cannot be undone.",
            ),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setDialogState) => TextFormField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: "Current password",
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip:
                        obscurePassword ? "Show password" : "Hide password",
                    onPressed: () => setDialogState(
                      () => obscurePassword = !obscurePassword,
                    ),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? "Enter your current password"
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text("Keep account"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(dialogContext, passwordController.text);
            }
          },
          child: const Text("Delete permanently"),
        ),
      ],
    ),
  );
  passwordController.dispose();
  return result;
}
