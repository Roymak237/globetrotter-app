import "package:flutter/material.dart";
import "package:globetrotter/providers/auth_provider.dart";
import "package:provider/provider.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                setState(() => _error = null);
                try {
                  await context
                      .read<AuthProvider>()
                      .login(
                        username: _usernameController.text.trim(),
                        password: _passwordController.text,
                      );
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, "/home");
                  }
                } catch (e) {
                  setState(() => _error = e.toString());
                }
              },
              child: const Text("Login"),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, "/register"),
              child: const Text("Create an account"),
            ),
          ],
        ),
      ),
    );
  }
}
