import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:provider/provider.dart";

import "localization/app_localizations.dart";
import "providers/auth_provider.dart";
import "providers/favorites_provider.dart";
import "providers/locale_provider.dart";
import "screens/create_itinerary_screen.dart";
import "screens/destination_detail_screen.dart";
import "screens/home_screen.dart";
import "screens/itineraries_screen.dart";
import "screens/itinerary_detail_screen.dart";
import "screens/login_screen.dart";
import "screens/map_screen.dart";
import "screens/profile_screen.dart";
import "screens/register_screen.dart";
import "screens/saved_destinations_screen.dart";
import "utils/theme.dart";

class GlobetrotterApp extends StatelessWidget {
  const GlobetrotterApp({super.key});

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
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
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
            routes: {
              "/login": (_) => const LoginScreen(),
              "/register": (_) => const RegisterScreen(),
              "/saved": (_) => const SavedDestinationsScreen(),
              "/destination_detail": (_) => const DestinationDetailScreen(),
              "/home": (_) => const HomeScreen(),
              "/map": (_) => const MapScreen(),
              "/itineraries": (_) => const ItinerariesScreen(),
              "/create_itinerary": (_) => const CreateItineraryScreen(),
              "/itinerary_detail": (_) => const ItineraryDetailScreen(),
              "/profile": (_) => const ProfileScreen(),
            },
          );
        },
      ),
    );
  }
}

class _SupportedMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _SupportedMaterialLocalizationsDelegate();

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
