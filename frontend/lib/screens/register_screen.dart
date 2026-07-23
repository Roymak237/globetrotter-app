import "package:flutter/material.dart";
import "../providers/auth_provider.dart";
import "package:provider/provider.dart";

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _prefsController = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            TextField(
              controller: _prefsController,
              decoration: const InputDecoration(
                labelText: "Preferences (comma-separated, e.g. beach, food)",
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                setState(() => _error = null);
                final prefs = _prefsController.text
                    .split(",")
                    .map((e) => e.trim().toLowerCase())
                    .where((e) => e.isNotEmpty)
                    .toList();
                try {
                  await context
                      .read<AuthProvider>()
                      .register(
                        username: _usernameController.text.trim(),
                        password: _passwordController.text,
                        preferences: prefs,
                      );
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, "/home");
                  }
                } catch (e) {
                  setState(() => _error = e.toString());
                }
              },
              child: const Text("Register"),
            ),
          ],
        ),
      ),
    );
  }
}
