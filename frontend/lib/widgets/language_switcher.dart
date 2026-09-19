import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../localization/app_localizations.dart";
import "../providers/locale_provider.dart";
import "../utils/theme.dart";

class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  static const _languages = <Locale>[
    Locale("en"),
    Locale("fr"),
    Locale("cpe"),
  ];

  String _code(Locale locale) => locale.languageCode.toUpperCase();

  String _name(AppLocalizations localizations, Locale locale) {
    switch (locale.languageCode) {
      case "fr":
        return localizations.french;
      case "cpe":
        return localizations.pidgin;
      default:
        return localizations.english;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final localizations = AppLocalizations.of(context);
    final selectedCode = _code(localeProvider.locale);

    return Semantics(
      label: localizations.language,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = MediaQuery.sizeOf(context).width < 470;
          if (compact) {
            return PopupMenuButton<Locale>(
              tooltip: localizations.language,
              initialValue: localeProvider.locale,
              onSelected: localeProvider.setLocale,
              itemBuilder: (context) => _languages
                  .map(
                    (locale) => PopupMenuItem<Locale>(
                      value: locale,
                      child: Text(
                        "${_code(locale)}  ${_name(localizations, locale)}",
                      ),
                    ),
                  )
                  .toList(),
              child: _LanguagePill(
                code: selectedCode,
                showChevron: true,
              ),
            );
          }

          return Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _languages.map((locale) {
                final selected =
                    locale.languageCode == localeProvider.locale.languageCode;
                return InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => localeProvider.setLocale(locale),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      _code(locale),
                      style: TextStyle(
                        color: selected ? Colors.white : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  final String code;
  final bool showChevron;

  const _LanguagePill({
    required this.code,
    required this.showChevron,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.expand_more_rounded,
              color: AppTheme.textSecondary,
              size: 17,
            ),
          ],
        ],
      ),
    );
  }
}
