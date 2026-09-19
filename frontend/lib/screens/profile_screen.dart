import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../models/user.dart";
import "../providers/auth_provider.dart";
import "../utils/preferences.dart";
import "../utils/theme.dart";
import "../widgets/account_dialogs.dart";
import "../widgets/preference_editor_dialog.dart";
import "../widgets/rate_app_dialog.dart";
import "interests_screen.dart";
import "suggest_place_screen.dart";

class ProfileScreen extends StatefulWidget {
  final bool showScaffold;

  const ProfileScreen({super.key, this.showScaffold = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _accountActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      await context.read<AuthProvider>().fetchProfile();
    } catch (_) {
      // The content state below gives the user a clear recovery path.
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _editPreferences() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final changed = await showPreferenceEditor(
      context,
      initialPreferences: user.preferences.toSet(),
      onSave: (preferences) async {
        await auth.updatePreferences(preferences: preferences);
      },
    );
    if (!mounted || !changed) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Travel signals updated")),
    );
  }

  Future<void> _editAccountDetails() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final changed = await showAccountDetailsEditor(
      context,
      user: user,
      onSave: (displayName, email, homeRegion, avatarUrl) async {
        await auth.updateProfile(
          displayName: displayName,
          email: email,
          homeRegion: homeRegion,
          avatarUrl: avatarUrl,
        );
      },
    );
    if (!mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile details updated")),
    );
  }

  Future<void> _changeUsername() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final changed = await showUsernameChangeDialog(
      context,
      currentUsername: user.username,
      onSave: (input) async {
        await auth.updateUsername(
          username: input.username,
          currentPassword: input.currentPassword,
        );
      },
    );
    if (!mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Username updated")),
    );
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthProvider>();
    final changed = await showPasswordChangeDialog(
      context,
      onSave: (input) async {
        await auth.updatePassword(
          currentPassword: input.currentPassword,
          newPassword: input.newPassword,
        );
      },
    );
    if (!mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Password updated")),
    );
  }

  Future<void> _revokeOtherSessions() async {
    final confirmed = await showConfirmAccountAction(
      context,
      title: "Sign out other devices?",
      message:
          "Every other active session will stop working. This device will stay signed in.",
      confirmLabel: "Sign out others",
    );
    if (!confirmed || !mounted) return;

    setState(() => _accountActionLoading = true);
    try {
      await context.read<AuthProvider>().revokeOtherSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Other sessions signed out")),
        );
      }
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _accountActionLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final password = await showDeleteAccountDialog(context);
    if (password == null || !mounted) return;

    setState(() => _accountActionLoading = true);
    try {
      await context.read<AuthProvider>().deleteAccount(
            currentPassword: password,
          );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, "/login", (route) => false);
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _accountActionLoading = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst("Exception: ", "")),
        backgroundColor: AppTheme.secondary,
      ),
    );
  }

  Widget _buildAvatar(User user) {
    final initials =
        user.username.isNotEmpty ? user.username[0].toUpperCase() : "?";
    if (user.avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: AppTheme.accent,
        child: Text(
          initials,
          style: const TextStyle(
            fontFamily: AppTheme.displayFontFamily,
            fontSize: 28,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 34,
      backgroundColor: AppTheme.accent,
      child: ClipOval(
        child: Image.network(
          user.avatarUrl,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Text(
            initials,
            style: const TextStyle(
              fontFamily: AppTheme.displayFontFamily,
              fontSize: 28,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (user == null) {
      return _ProfileMessage(
        icon: Icons.person_off_outlined,
        title: "Your profile is taking a detour.",
        message: "We could not load your details right now.",
        action: TextButton.icon(
          onPressed: _loadProfile,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text("Try again"),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
            ),
            child: Row(
              children: [
                _buildAvatar(user),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "YOUR TRAVEL PROFILE",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        user.displayName.isNotEmpty
                            ? user.displayName
                            : user.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontFamily: AppTheme.displayFontFamily,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "@${user.username}",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSurface(
            title: "Account details",
            subtitle: "The small details that make this map yours.",
            children: [
              _SettingsRow(
                icon: Icons.edit_outlined,
                title: "Edit profile details",
                subtitle: user.email.isEmpty
                    ? "Add a display name, email, region, or avatar"
                    : user.email,
                onTap: _accountActionLoading ? null : _editAccountDetails,
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.alternate_email_rounded,
                title: "Change username",
                subtitle: "Updates your itinerary and share ownership",
                onTap: _accountActionLoading ? null : _changeUsername,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSurface(
            title: "Your travel signals",
            subtitle:
                "These details help shape recommendations that feel more like you.",
            trailing: TextButton.icon(
              onPressed: _accountActionLoading ? null : _editPreferences,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text("Edit"),
            ),
            children: [
              if (user.preferences.isEmpty)
                _ProfileMessage(
                  icon: Icons.tune_rounded,
                  title: "No preferences yet",
                  message:
                      "Add a few interests to make your next recommendation more personal.",
                  action: OutlinedButton.icon(
                    onPressed: _accountActionLoading ? null : _editPreferences,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text("Choose interests"),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: user.preferences.map((preference) {
                    return Chip(
                      label: Text(preferenceLabel(preference)),
                      avatar: const Icon(Icons.check_rounded, size: 16),
                      backgroundColor: AppTheme.primarySoft,
                      labelStyle: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSurface(
            title: "Community",
            subtitle: "Shape your feed and help the catalogue grow.",
            children: [
              _SettingsRow(
                icon: Icons.interests_outlined,
                title: AppLocalizations.of(context).interestsTitle,
                subtitle: AppLocalizations.of(context).interestsSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InterestsScreen()),
                ),
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.add_location_alt_outlined,
                title: AppLocalizations.of(context).suggestPlaceTitle,
                subtitle: AppLocalizations.of(context).suggestPlaceSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SuggestPlaceScreen()),
                ),
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.star_outline_rounded,
                title: AppLocalizations.of(context).rateAppTitle,
                subtitle: AppLocalizations.of(context).rateAppPrompt,
                onTap: () => RateAppDialog.show(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSurface(
            title: "Account security",
            subtitle: "Keep access to your travel notes in your hands.",
            children: [
              _SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: "Change password",
                subtitle: "Verify your current password first",
                onTap: _accountActionLoading ? null : _changePassword,
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.devices_outlined,
                title: "Sign out other devices",
                subtitle: "Keep this device active and revoke other sessions",
                onTap: _accountActionLoading ? null : _revokeOtherSessions,
              ),
              const Divider(height: 1),
              _SettingsRow(
                icon: Icons.delete_outline_rounded,
                title: "Delete account",
                subtitle: "Permanently remove profile, trips, and shares",
                destructive: true,
                onTap: _accountActionLoading ? null : _deleteAccount,
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _accountActionLoading
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await auth.logout();
                    if (!mounted) return;
                    navigator.pushNamedAndRemoveUntil(
                      "/login",
                      (route) => false,
                    );
                  },
            icon: const Icon(Icons.logout_rounded),
            label: const Text("LOG OUT"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!widget.showScaffold) return content;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: AppTheme.appBarBackground,
        title: Text(AppLocalizations.of(context).profileTitle),
      ),
      body: content,
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  const _SettingsSurface({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontFamily: AppTheme.displayFontFamily,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppTheme.secondary : AppTheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 3),
      enabled: onTap != null,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: destructive ? AppTheme.secondary : AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _ProfileMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.primary, size: 30),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: AppTheme.displayFontFamily,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
        ),
        if (action != null) ...[
          const SizedBox(height: 8),
          action!,
        ],
      ],
    );
  }
}
