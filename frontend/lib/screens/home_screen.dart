import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../providers/auth_provider.dart";
import "../utils/theme.dart";
import "../widgets/bottom_nav.dart";
import "../widgets/home_backdrop.dart";
import "../widgets/language_switcher.dart";
import "../widgets/notification_bell.dart";
import "chat_screen.dart";
import "destinations_screen.dart";
import "itineraries_screen.dart";
import "map_screen.dart";
import "profile_screen.dart";
import "recommendations_screen.dart";
import "saved_destinations_screen.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final localizations = AppLocalizations.of(context);
    final greetingName = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : user?.username.isNotEmpty == true
            ? user!.username
            : "traveler";
    final pages = [
      const DestinationsScreen(),
      const RecommendationsScreen(),
      SavedDestinationsScreen(
        showScaffold: false,
        onExplore: () => setState(() => _currentIndex = 0),
      ),
      MapScreen(isActive: _currentIndex == 3),
      const ItinerariesScreen(),
      const ChatScreen(showScaffold: false),
      const ProfileScreen(showScaffold: false),
    ];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(94),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppTheme.background,
          foregroundColor: AppTheme.textPrimary,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          localizations.brand,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.secondary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          localizations.hello(greetingName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontFamily: AppTheme.displayFontFamily,
                                height: 1,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const NotificationBell(),
                  const LanguageSwitcher(),
                ],
              ),
            ),
          ),
        ),
      ),
      body: HomeBackdrop(
        child: IndexedStack(index: _currentIndex, children: pages),
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
