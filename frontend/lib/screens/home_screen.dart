import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../providers/auth_provider.dart";
import "../widgets/bottom_nav.dart";
import "destinations_screen.dart";
import "recommendations_screen.dart";
import "itineraries_screen.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _pages = <Widget>[
    const DestinationsScreen(),
    const RecommendationsScreen(),
    const ItinerariesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final username = context.watch<AuthProvider>().currentUser?.username ?? "Traveler";
    return Scaffold(
      appBar: AppBar(title: Text("Hi, $username")),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
