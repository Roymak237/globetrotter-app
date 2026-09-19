import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:provider/provider.dart";

import "localization/app_localizations.dart";
import "providers/auth_provider.dart";
import "providers/favorites_provider.dart";
import "providers/locale_provider.dart";
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
  const GlobetrotterApp({super.key});

  /// Held at the app level so an incoming call can open its screen from
  /// wherever the traveller happens to be, including a background tab.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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
            supportedLocales: const [
              Locale("en"),
              Locale("fr"),
              Locale("cpe"),
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              _SupportedMaterialLocalizationsDelegate(),
              _SupportedWidgetsLocalizationsDelegate(),
              _SupportedCupertinoLocalizationsDelegate(),
            ],
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.theme,
            initialRoute: "/login",
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
            },
          );
        },
      ),
    );
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

class _SupportedMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {  const _SupportedMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    final delegate = GlobalMaterialLocalizations.delegate;
    return delegate.isSupported(locale)
        ? delegate.load(locale)
        : delegate.load(const Locale("en"));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) =>
      false;
}

class _SupportedWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _SupportedWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) async {
    final delegate = GlobalWidgetsLocalizations.delegate;
    return delegate.isSupported(locale)
        ? delegate.load(locale)
        : delegate.load(const Locale("en"));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<WidgetsLocalizations> old) =>
      false;
}

class _SupportedCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _SupportedCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) async {
    final delegate = GlobalCupertinoLocalizations.delegate;
    return delegate.isSupported(locale)
        ? delegate.load(locale)
        : delegate.load(const Locale("en"));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) =>
      false;
}
