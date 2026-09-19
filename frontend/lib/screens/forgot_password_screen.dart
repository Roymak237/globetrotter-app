import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../providers/auth_provider.dart";
import "../utils/theme.dart";

/// Two-step password reset: ask for a code, then use it to set a new password.
///
/// This deployment has no mail server, so the backend hands the code straight
/// back and it is shown on screen. That is stated plainly rather than dressed
/// up as an email, because a traveller who cannot get into their account at
/// all will not be helped by this screen and should know that up front.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  bool _codeIssued = false;
  String? _issuedCode;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = "Enter your username or email address.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await context.read<AuthProvider>().requestPasswordReset(
            identifier: identifier,
          );
      if (!mounted) return;
      setState(() {
        _codeIssued = true;
        _issuedCode = code;
        if (code != null) _code.text = code;
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst("Exception: ", ""));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitReset() async {
    final code = _code.text.trim();
    final password = _password.text;

    if (code.isEmpty) {
      setState(() => _error = "Enter the reset code.");
      return;
    }
    if (password.length < 8) {
      setState(() => _error = "Password must be at least 8 characters.");
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = "The two passwords do not match.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().resetPassword(
            identifier: _identifier.text.trim(),
            code: code,
            newPassword: password,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password updated. Sign in with your new password."),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst("Exception: ", ""));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset password")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              _codeIssued ? "Step 2 of 2" : "Step 1 of 2",
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _codeIssued
                  ? "Enter the code and choose a new password."
                  : "Tell us who you are and we will issue a reset code.",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: AppTheme.displayFontFamily,
                  ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _identifier,
              enabled: !_codeIssued && !_busy,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: "Username or email",
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            if (_codeIssued) ...[
              const SizedBox(height: 16),
              if (_issuedCode != null) _codeNotice(),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: "Reset code",
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "New password",
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Confirm new password",
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _busy ? null : (_codeIssued ? _submitReset : _requestCode),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_codeIssued ? "Set new password" : "Send reset code"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your reset code",
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _issuedCode!,
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "This app has no mail server yet, so the code is shown here "
            "instead of being emailed. It expires in 15 minutes.",
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
