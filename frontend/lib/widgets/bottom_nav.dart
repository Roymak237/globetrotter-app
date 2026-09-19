import "package:flutter/material.dart";

import "../localization/app_localizations.dart";
import "../utils/theme.dart";

class BottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  final _scrollController = ScrollController();
  final _itemKeys = List.generate(7, (_) => GlobalKey());

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _select(int index) {
    widget.onTap(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = _itemKeys[index].currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final items = [
      (
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: localizations.navDestinations,
      ),
      (
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: localizations.navRecommendations,
      ),
      (
        icon: Icons.favorite_border_rounded,
        activeIcon: Icons.favorite_rounded,
        label: localizations.navFavorites,
      ),
      (
        icon: Icons.map_outlined,
        activeIcon: Icons.map_rounded,
        label: localizations.navMap,
      ),
      (
        icon: Icons.route_outlined,
        activeIcon: Icons.route_rounded,
        label: localizations.navItineraries,
      ),
      (
        icon: Icons.forum_outlined,
        activeIcon: Icons.forum_rounded,
        label: localizations.navChat,
      ),
      (
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: localizations.navProfile,
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        6,
        12,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: false,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = index == widget.currentIndex;
              return _NavItem(
                key: _itemKeys[index],
                icon: isSelected ? item.activeIcon : item.icon,
                label: item.label,
                selected: isSelected,
                onTap: () => _select(index),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: BoxConstraints(minWidth: selected ? 96 : 52),
          padding: EdgeInsets.symmetric(horizontal: selected ? 13 : 14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : AppTheme.textSecondary,
                size: 21,
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
