import "package:flutter/material.dart";

class AppTheme {
  // The palette is the marketing site's, carried into the product so the two
  // read as one thing. The site is a forced-dark, near-monochrome page with a
  // single steel-blue accent gradient, declared in landing-react/src/index.css
  // as raw HSL triples:
  //
  //   --bg 0 0% 4%   --surface 0 0% 8%   --stroke 0 0% 12%
  //   --text 0 0% 96%   --muted 0 0% 53%
  //   accent-gradient  #89AACC -> #4E85BF
  //
  // Those six values are reproduced exactly below wherever a token has a
  // direct counterpart; everything else is derived from them. Changing the
  // site's CSS variables without changing this block is what would make the
  // app and the page drift apart again.
  //
  // One consequence is worth stating plainly, because it inverts the usual
  // reading of these names: on a dark interface the *readable* end of a ramp
  // is the light end. `primaryDark` is therefore lighter than `primary`, not
  // darker. The names describe each token's job — foreground on a tinted
  // container — rather than its luminance.

  /// Accent-gradient start. Light enough to carry body text and icons on any
  /// dark surface here, which is most of what the brand colour is used for.
  static const Color primary = Color(0xFF89AACC);

  /// Ink for anything sitting *on* [primary]. The brand colour is a light fill
  /// in this theme, so a filled button is a pale pill with dark type — the
  /// same treatment the site gives its one solid call to action. White on
  /// [primary] measures 2.2:1 and must never be used.
  static const Color onPrimary = Color(0xFF07101A);

  /// Foreground on the tinted containers below ([primarySoft], [accentSoft]).
  /// Pale rather than deep, for the reason given at the top of this block.
  static const Color primaryDark = Color(0xFFA8C6E2);

  /// Accent-gradient end, used where a second, quieter brand tone is wanted.
  static const Color secondary = Color(0xFF6E9BC9);

  /// The palest step. Highlights that must out-rank [primary] without becoming
  /// plain white — ratings, counts, labels over photography.
  static const Color accent = Color(0xFFC9DCEE);

  /// Page. `--bg`, 0 0% 4%.
  static const Color background = Color(0xFF0A0A0A);

  /// Cards, inputs, sheets and tiles. `--surface`, 0 0% 8%.
  ///
  /// Four steps above [background] rather than level with it: the site relies
  /// on the same small gap to let a card read as a card without a shadow, and
  /// a surface equal to the page would dissolve every boundary in the app.
  static const Color surface = Color(0xFF141414);

  /// One step *below* [surface], for panels that sit on a surface and need to
  /// be told apart from it — a quoted reply inside a bubble, an inset preview
  /// strip. On a dark interface receding means darker, so this is darker than
  /// the surface it insets into rather than lighter.
  static const Color surfaceSunken = Color(0xFF0E0E0E);

  /// Hairlines. `--stroke` is 0 0% 12% (#1F1F1F) on the site, where strokes
  /// mostly sit on the page colour. Here they more often sit on [surface],
  /// which is itself 0 0% 8%, so the token is lifted two steps to keep an
  /// input's edge visible; against the page it still reads as the same line.
  static const Color border = Color(0xFF262626);

  /// Tinted container in the brand hue. Pairs with [primaryDark] at 9.4:1.
  static const Color primarySoft = Color(0xFF141F2B);

  /// The cooler, flatter tint, for chips and secondary groupings.
  static const Color accentSoft = Color(0xFF18212B);

  static const Color error = Color(0xFFF06A6F);

  /// `--text`, 0 0% 96%.
  static const Color textPrimary = Color(0xFFF5F5F5);

  /// `--muted`, 0 0% 53%, lifted a shade. The site uses the muted tone almost
  /// exclusively for short labels on the page colour; the app also puts it on
  /// [surface], where 0 0% 53% lands at 5.2:1 and small print starts to go. At
  /// 0 0% 56% it clears 5.8:1 on surface and 6.5:1 on the page.
  static const Color textSecondary = Color(0xFF8F8F8F);

  /// Midpoint of the brand sweep. Pulling it out keeps the three-stop gradient
  /// from collapsing into a flat band where the two accent stops meet.
  static const Color brandMid = Color(0xFF1A3045);

  /// Deep end of the horizontal sweep, where the app bar finishes.
  static const Color brandDeep = Color(0xFF22405C);

  /// The disc behind the call and video buttons in the chat app bar.
  ///
  /// It exists so those controls read as controls against the gradient rather
  /// than as two icons floating on it. Darker than every stop of the sweep, so
  /// the white glyph on top clears 17:1 wherever the bar happens to be.
  static const Color callDisc = Color(0xFF0B1621);

  /// Cool counterpoint for states that must not borrow the brand — live
  /// location, informational badges.
  static const Color indigo = Color(0xFF8FB3D9);

  /// The incoming chat bubble. Dark, so the light body text reads on it.
  static const Color indigoSoft = Color(0xFF1C2838);

  /// Positive confirmations, so success never borrows the brand's blue.
  static const Color success = Color(0xFF5CBE7A);

  /// Depth on a dark interface comes from a darker shadow, not a tinted one.
  ///
  /// These shadows were previously drawn in the brand's deep end, which worked
  /// while that colour was a dark brown. Tinting a shadow with the light steel
  /// the token now holds would paint a halo around every raised element.
  static const Color shadow = Color(0xFF000000);

  /// The signature gradient. Used for primary calls to action and any surface
  /// that needs to feel like the brand rather than plain chrome.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E1B2B), brandMid, Color(0xFF2F5F8E)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Horizontal variant for wide, short surfaces such as app bars, where a
  /// diagonal sweep would be clipped to a single muddled band.
  ///
  /// Everything drawn on an app bar in this product is white, so the sweep is
  /// held entirely in the dark half of the ramp: its lightest point, [brandDeep],
  /// still carries white at 10.7:1, against the 4.5:1 floor for body text.
  static const LinearGradient brandGradientHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0C0C0C), Color(0xFF12202E), brandMid, brandDeep],
    stops: [0.0, 0.35, 0.72, 1.0],
  );

  /// Scrim laid over photography so white text stays legible. Tinted with the
  /// page colour rather than neutral black, so an image fades into the app
  /// instead of into a hole.
  static const LinearGradient photoScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xB3060606)],
  );

  /// Heavier scrim for full-bleed backgrounds behind forms.
  static const LinearGradient immersiveScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x8C050505), Color(0xF0050505)],
    stops: [0, 0.75],
  );

  /// Ready-made gradient fill for `AppBar.flexibleSpace`. `AppBarTheme` cannot
  /// express a gradient, so screens opt in by passing this widget.
  ///
  /// The `SizedBox.expand` child is load-bearing, not decoration. A
  /// `DecoratedBox` with no child sizes itself to `constraints.smallest`,
  /// and `flexibleSpace` hands down *loose* constraints, so without a child
  /// this laid out 800x0 and painted nothing at all. Screens that also set
  /// `backgroundColor: Colors.transparent` were then left with white icons
  /// on the bare scaffold colour.
  static const Widget appBarBackground = DecoratedBox(
    decoration: BoxDecoration(gradient: brandGradientHorizontal),
    child: SizedBox.expand(),
  );

  static const double radiusInput = 14;
  static const double radiusCard = 18;
  static const double radiusLarge = 28;

  // Use broadly available editorial fallbacks without requiring a network font
  // download at runtime. They keep the intended serif/sans contrast on desktop,
  // web, and mobile platforms. Georgia stands in for the site's Instrument
  // Serif and Trebuchet for Inter; both are the nearest metric-compatible
  // faces that ship everywhere.
  static const String displayFontFamily = "Georgia";
  static const String bodyFontFamily = "Trebuchet MS";

  static ThemeData get theme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = base.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
      fontFamily: bodyFontFamily,
      fontFamilyFallback: const ["Arial", "sans-serif"],
    );

    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primarySoft,
        onPrimaryContainer: primaryDark,
        secondary: secondary,
        onSecondary: onPrimary,
        secondaryContainer: accentSoft,
        onSecondaryContainer: accent,
        tertiary: accent,
        onTertiary: onPrimary,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: Color(0xFF1C1C1C),
        outline: border,
        error: error,
        onError: onPrimary,
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
        // A screen that forgets `flexibleSpace` must not end up with white on
        // white, so this has to be dark enough to carry white on its own. It
        // is the second stop of the sweep, which keeps the two consistent.
        backgroundColor: Color(0xFF12202E),
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
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusInput),
          ),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusInput),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
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
        // A selected chip is a pale pill, so its tick takes the dark ink. The
        // M3 default derives this from the label colour, which is correct for
        // the unselected state and invisible on the selected one.
        checkmarkColor: onPrimary,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      // The dark-theme default inverts the snackbar to a light slab, which on
      // this palette is the single brightest thing on screen and reads as an
      // error whatever it says.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primarySoft,
        contentTextStyle: const TextStyle(color: textPrimary),
        actionTextColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusInput),
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
