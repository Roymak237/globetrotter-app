import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../providers/auth_provider.dart";
import "../utils/theme.dart";
import "../widgets/auth_widgets.dart";
import "../widgets/travel_preference_selector.dart";

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final Set<String> _selectedPreferences = <String>{};
  String? _error;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _error = null;
      _loading = true;
    });

    final preferences = _selectedPreferences.toList();

    try {
      await context.read<AuthProvider>().register(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            preferences: preferences,
          );
      if (mounted) {
        Navigator.pushReplacementNamed(context, "/login");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AuthBackdrop(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 18),
            child: Row(
              children: [
                IconButton(
                  tooltip: localizations.backToLogin,
                  onPressed: _loading ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white,
                ),
                const SizedBox(width: 2),
                Text(
                  localizations.registerTopline,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontFamily: AppTheme.displayFontFamily,
                        height: 1.25,
                      ),
                ),
              ],
            ),
          ),
          AuthFormCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthIntro(
                    eyebrow: localizations.registerEyebrow,
                    title: localizations.registerTitle,
                    subtitle: localizations.registerSubtitle,
                    icon: Icons.map_rounded,
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    AuthErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: localizations.username,
                      hintText: localizations.registerUsernameHint,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return localizations.chooseUsername;
                      }
                      if (value.trim().length < 3) {
                        return localizations.useAtLeastThreeCharacters;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: localizations.password,
                      hintText: localizations.newPasswordHint,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? localizations.showPassword
                            : localizations.hidePassword,
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return localizations.choosePassword;
                      }
                      if (value.length < 8) {
                        return localizations.useAtLeastEightCharacters;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  TravelPreferenceSelector(
                    selected: _selectedPreferences,
                    onToggle: (preference) {
                      setState(() {
                        if (_selectedPreferences.contains(preference)) {
                          _selectedPreferences.remove(preference);
                        } else {
                          _selectedPreferences.add(preference);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 20),
                      label: Text(_loading
                          ? localizations.creatingAccount
                          : localizations.createAccount),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AuthDivider(label: localizations.alreadyHaveAccount),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: Text(localizations.returnToSignIn),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            localizations.registerFooter,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}
