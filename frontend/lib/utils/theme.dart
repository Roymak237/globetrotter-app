import "package:flutter/material.dart";

class AppTheme {
  // "Sahel" brand ramp, drawn from West and Central African earth pigments:
  // terracotta fired into clay, then ochre and the pale gold of millet. Every
  // widget reads its colour from here, so the ramp is the single place that
  // defines the product's identity.
  static const Color primary = Color(0xFFB4462A);
  static const Color primaryDark = Color(0xFF7A2E19);
  static const Color secondary = Color(0xFFD98E2B);
  static const Color accent = Color(0xFFE9C46A);
  static const Color background = Color(0xFFFAF5EE);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE7D9C6);
  static const Color primarySoft = Color(0xFFF7E4D9);
  static const Color accentSoft = Color(0xFFFBEFD5);
  static const Color error = Color(0xFFB3261E);
  static const Color textPrimary = Color(0xFF2C1A10);
  static const Color textSecondary = Color(0xFF7B6553);

  /// Midpoint of the ramp. Pulling it out keeps the three-stop gradient from
  /// collapsing into a flat band where terracotta meets ochre.
  static const Color clay = Color(0xFFC9703A);

  /// Adire indigo: the cool counterpoint the warm ramp needs. Reserved for
  /// surfaces that must read as distinct from the brand — incoming chat
  /// bubbles, unread badges and informational states.
  static const Color indigo = Color(0xFF1F3A63);
  static const Color indigoSoft = Color(0xFFE2E8F2);

  /// Sap green, the third pigment in a mudcloth palette. Used for positive
  /// confirmations so success never borrows the brand's own terracotta.
  static const Color success = Color(0xFF4F7A3F);

  /// The signature gradient. Used for app bars, primary calls to action and
  /// any surface that needs to feel like the brand rather than plain chrome.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, clay, secondary],
    stops: [0.0, 0.55, 1.0],
  );

  /// Horizontal variant for wide, short surfaces such as app bars, where a
  /// diagonal sweep would be clipped to a single muddled band.
  static const LinearGradient brandGradientHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryDark, primary, clay, secondary],
    stops: [0.0, 0.35, 0.72, 1.0],
  );

  /// Scrim laid over photography so white text stays legible. Tinted with the
  /// dark cocoa end of the ramp instead of neutral black, which keeps images
  /// feeling part of the brand rather than washed out.
  static const LinearGradient photoScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0x7A2B1508)],
  );

  /// Heavier scrim for full-bleed backgrounds behind forms.
  static const LinearGradient immersiveScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x73201007), Color(0xD9201007)],
    stops: [0, 0.75],
  );

  /// Ready-made gradient fill for `AppBar.flexibleSpace`. `AppBarTheme` cannot
  /// express a gradient, so screens opt in by passing this widget.
  static const Widget appBarBackground = DecoratedBox(
    decoration: BoxDecoration(gradient: brandGradientHorizontal),
  );

  static const double radiusInput = 14;
  static const double radiusCard = 18;
  static const double radiusLarge = 28;

  // Use broadly available editorial fallbacks without requiring a network font
  // download at runtime. They keep the intended serif/sans contrast on desktop,
  // web, and mobile platforms.
  static const String displayFontFamily = "Georgia";
  static const String bodyFontFamily = "Trebuchet MS";

  static ThemeData get theme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = base.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
      fontFamily: bodyFontFamily,
      fontFamilyFallback: const ["Arial", "sans-serif"],
    );

    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primarySoft,
        onPrimaryContainer: primaryDark,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFBEFD5),
        onSecondaryContainer: Color(0xFF7A4A08),
        tertiary: accent,
        onTertiary: textPrimary,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: Color(0xFFF2EADF),
        error: error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: background,
      textTheme: textTheme.copyWith(
        displaySmall: textTheme.displaySmall?.copyWith(
          fontFamily: displayFontFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontFamily: displayFontFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontFamily: displayFontFamily,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontFamily: displayFontFamily,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontFamily: displayFontFamily,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: false,
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: const BorderSide(color: error, width: 1.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusInput),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 50),
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusInput),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: primary,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
