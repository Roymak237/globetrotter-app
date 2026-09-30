import "package:flutter/material.dart";

import "../models/user.dart";
import "../utils/regions.dart";
import "../utils/theme.dart";
import "user_avatar.dart";

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
  /// Picks an image, uploads it and returns the stored path
  /// (`/api/media/<id>.jpg`), or null if the user cancelled.
  ///
  /// Injected rather than built here so this dialog keeps no dependency on
  /// the network or the file picker, which is what lets it be driven in a
  /// widget test.
  Future<String?> Function()? onPickAvatar,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _AccountDetailsDialog(
      user: user,
      onSave: onSave,
      onPickAvatar: onPickAvatar,
    ),
  );
  return result == true;
}

/// A real widget rather than a `StatefulBuilder` over local variables.
///
/// The previous version created its `TextEditingController`s beside the
/// `showDialog` call and disposed them on the line after it returned. That
/// return happens when the route is popped, not when it has finished leaving:
/// the dialog keeps rebuilding through its exit animation, and those rebuilds
/// reach controllers that have already been disposed. It throws "A
/// TextEditingController was used after being disposed" every time the dialog
/// closes. Owning them here ties disposal to the element's own lifetime, which
/// is the point at which nothing can still be painting them.
///
/// The other dialogs in this file share the original pattern and the same
/// latent fault.
class _AccountDetailsDialog extends StatefulWidget {
  final User user;
  final Future<void> Function(
    String displayName,
    String email,
    String homeRegion,
    String avatarUrl,
  ) onSave;
  final Future<String?> Function()? onPickAvatar;

  const _AccountDetailsDialog({
    required this.user,
    required this.onSave,
    this.onPickAvatar,
  });

  @override
  State<_AccountDetailsDialog> createState() => _AccountDetailsDialogState();
}

class _AccountDetailsDialogState extends State<_AccountDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _emailController;
  late String _avatarUrl;
  String? _selectedRegion;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _displayNameController = TextEditingController(text: user.displayName);
    _emailController = TextEditingController(text: user.email);
    _avatarUrl = user.avatarUrl;
    _selectedRegion = user.homeRegion.isEmpty ? null : user.homeRegion;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final pick = widget.onPickAvatar;
    if (pick == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final picked = await pick();
      if (!mounted) return;
      setState(() {
        _uploading = false;
        // A cancelled pick must leave the existing photo alone rather than
        // clear it.
        if (picked != null) _avatarUrl = picked;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _displayNameController.text.trim(),
        _emailController.text.trim(),
        _selectedRegion ?? "",
        _avatarUrl,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final busy = _saving || _uploading;

    return AlertDialog(
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
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _displayNameController,
                  enabled: !_saving,
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
                  controller: _emailController,
                  enabled: !_saving,
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
                  initialValue: _selectedRegion,
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
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _selectedRegion = value),
                ),
                const SizedBox(height: 13),
                // The photo control, not a URL box.
                //
                // This field used to ask for a public https:// address and
                // even validated for one, but the backend only accepts its own
                // /api/media/<id> paths and rejected every such URL with 400
                // "avatar must be an uploaded image". The feature could not
                // succeed: the client validated for exactly what the server
                // refused. Uploading is the flow the API was built for, and it
                // is what group photos already use.
                Row(
                  children: [
                    UserAvatar(
                      avatarUrl: _avatarUrl,
                      name: user.displayName.isEmpty
                          ? user.username
                          : user.displayName,
                      radius: 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Profile photo",
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _avatarUrl.isEmpty
                                ? "Using your initials"
                                : "Photo set",
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    busy || widget.onPickAvatar == null
                                        ? null
                                        : _pickAvatar,
                                icon: _uploading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.photo_camera_outlined,
                                        size: 18),
                                label: Text(
                                  _uploading
                                      ? "Uploadingâ€¦"
                                      : _avatarUrl.isEmpty
                                          ? "Upload photo"
                                          : "Change photo",
                                ),
                              ),
                              if (_avatarUrl.isNotEmpty)
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => setState(() => _avatarUrl = ""),
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  label: const Text("Remove"),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton.icon(
          onPressed: busy ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_saving ? "Savingâ€¦" : "Save profile"),
        ),
      ],
    );
  }
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
                    return "Use 3â€“30 lowercase letters, numbers, or _";
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
            child: Text(saving ? "Updatingâ€¦" : "Change username"),
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
            child: Text(saving ? "Updatingâ€¦" : "Change password"),
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
