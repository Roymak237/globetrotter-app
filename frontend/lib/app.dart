import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "providers/auth_provider.dart";
import "screens/splash_screen.dart";
import "screens/login_screen.dart";
import "screens/register_screen.dart";
import "screens/home_screen.dart";
import "screens/create_itinerary_screen.dart";
import "screens/itinerary_detail_screen.dart";
import "utils/theme.dart";

class GlobetrotterApp extends StatelessWidget {
  const GlobetrotterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: "GlobeTrotter Cameroon",
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        initialRoute: "/",
        routes: {
          "/": (_) => const SplashScreen(),
          "/login": (_) => const LoginScreen(),
          "/register": (_) => const RegisterScreen(),
          "/home": (_) => const HomeScreen(),
          "/create_itinerary": (_) => const CreateItineraryScreen(),
          "/itinerary_detail": (_) => const ItineraryDetailScreen(),
        },
      ),
    );
  }
}
