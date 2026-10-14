import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:provider/provider.dart";

import "localization/app_localizations.dart";
import "providers/auth_provider.dart";
import "providers/favorites_provider.dart";
import "providers/locale_provider.dart";
import "screens/about_developer_screen.dart";
import "screens/call_screen.dart";
import "screens/create_itinerary_screen.dart";
import "screens/destination_detail_screen.dart";
import "screens/forgot_password_screen.dart";
import "screens/home_screen.dart";
import "screens/itineraries_screen.dart";
import "screens/itinerary_detail_screen.dart";
import "screens/login_screen.dart";
import "screens/map_screen.dart";
import "screens/profile_screen.dart";
import "screens/register_screen.dart";
import "screens/saved_destinations_screen.dart";
import "services/call_service.dart";
import "utils/theme.dart";

class GlobetrotterApp extends StatelessWidget {
  /// Supplied only by tests, so the startup gate can be exercised against a
  /// stub server instead of the live one. Null in the shipped app.
  final http.Client? authClient;

  const GlobetrotterApp({super.key, this.authClient});

  /// Held at the app level so an incoming call can open its screen from
  /// wherever the traveller happens to be, including a background tab.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(client: authClient)),
        ChangeNotifierProvider(
          create: (_) => FavoritesProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocaleProvider()..load(),
        ),
        ChangeNotifierProvider(create: (_) => CallService()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.theme,
            home: const StartupGate(),
            builder: (context, child) =>
                _CallGateway(child: child ?? const SizedBox.shrink()),
            routes: {
              "/login": (_) => const LoginScreen(),
              "/register": (_) => const RegisterScreen(),
              "/forgot_password": (_) => const ForgotPasswordScreen(),
              "/saved": (_) => const SavedDestinationsScreen(),
              "/destination_detail": (_) => const DestinationDetailScreen(),
              "/home": (_) => const HomeScreen(),
              "/map": (_) => const MapScreen(),
              "/itineraries": (_) => const ItinerariesScreen(),
              "/create_itinerary": (_) => const CreateItineraryScreen(),
              "/itinerary_detail": (_) => const ItineraryDetailScreen(),
              "/profile": (_) => const ProfileScreen(),
              "/call": (_) => const CallScreen(),
              "/about_developer": (_) => const AboutDeveloperScreen(),
            },
          );
        },
      ),
    );
  }
}

/// Decides whether a cold launch opens the app or the sign-in screen.
///
/// Signing in stores a token, but nothing ever read it back, so every launch
/// began at the sign-in screen no matter how recently the traveller signed in.
/// This reads the stored session before the first screen is chosen.
///
/// The decision is made offline, from disk alone. Confirming with the server
/// first would mean that a traveller with no signal — on a bus, in a valley,
/// out of credit — is shown a sign-in screen they cannot get past, which is
/// worse than briefly trusting a session that turns out to be stale. The
/// server is consulted immediately afterwards, and only a definite rejection
/// sends anyone back to sign in.
class StartupGate extends StatefulWidget {
  /// Overridable so tests can assert which way the gate went without
  /// mounting the whole home screen, whose timers and animations never
  /// settle under the test binding. Default to the real screens.
  final WidgetBuilder signedIn;
  final WidgetBuilder signedOut;

  const StartupGate({
    super.key,
    this.signedIn = _buildHome,
    this.signedOut = _buildLogin,
  });

  static Widget _buildHome(BuildContext _) => const HomeScreen();
  static Widget _buildLogin(BuildContext _) => const LoginScreen();

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _checking = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final auth = context.read<AuthProvider>();
    try {
      await auth.loadToken();
    } catch (_) {
      // Unreadable storage is not a reason to fail the launch; it just means
      // there is no session to restore.
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _signedIn = auth.isAuthenticated;
    });
    if (!auth.isAuthenticated) return;

    // Verify in the background. The traveller is already in the app by now.
    final stillValid = await auth.refreshSession();
    if (!mounted || stillValid) return;
    setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _signedIn ? widget.signedIn(context) : widget.signedOut(context);
  }
}

/// Keeps the call signalling socket connected for as long as someone is signed
/// in, and opens the call screen when a call arrives.
///
/// This sits above the navigator rather than inside any one screen, because a
/// traveller browsing destinations should still be reachable by a call.
class _CallGateway extends StatefulWidget {
  final Widget child;

  const _CallGateway({required this.child});

  @override
  State<_CallGateway> createState() => _CallGatewayState();
}

class _CallGatewayState extends State<_CallGateway> {
  String? _connectedFor;

  @override
  void initState() {
    super.initState();
    context.read<CallService>().onIncomingCall = (_) {
      final navigator = GlobetrotterApp.navigatorKey.currentState;
      navigator?.pushNamed("/call");
    };
  }

  @override
  Widget build(BuildContext context) {
    // Watching here rather than in initState means sign-in and sign-out are
    // both picked up; the work itself is deferred to after the frame so the
    // service never calls notifyListeners while a build is in progress.
    final token = context.watch<AuthProvider>().token;
    final username = context.watch<AuthProvider>().currentUser?.username ?? "";

    if (token != _connectedFor) {
      _connectedFor = token;
      final calls = context.read<CallService>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (token == null) {
          calls.disconnect();
        } else {
          calls.connect(token, username);
        }
      });
    }

    return widget.child;
  }
}
