import 'package:flutter/material.dart';

/// Material 3 Expressive (MD3E) Color Tokens
/// Combining Spotify's signature vibrancy with Google Material 3 Expressive tonal surface hierarchy.
class MD3EColors {
  MD3EColors._();

  // Signature Spotify Vibrancy
  static const Color spotifyGreen = Color(0xFF1ED760);
  static const Color spotifyGreenDark = Color(0xFF1DB954);
  static const Color spotifyBlack = Color(0xFF121212);

  // M3 Expressive Dark Surface Hierarchy
  static const Color surfaceDim = Color(0xFF0F1014);
  static const Color surface = Color(0xFF121318);
  static const Color surfaceBright = Color(0xFF2E2F38);
  static const Color surfaceContainerLowest = Color(0xFF0A0B0E);
  static const Color surfaceContainerLow = Color(0xFF16171E);
  static const Color surfaceContainer = Color(0xFF1C1D26);
  static const Color surfaceContainerHigh = Color(0xFF23242F);
  static const Color surfaceContainerHighest = Color(0xFF2C2D3B);

  // On Surface & Text
  static const Color onSurface = Color(0xFFE4E1E9);
  static const Color onSurfaceVariant = Color(0xFFA5A4B2);
  static const Color outline = Color(0xFF494A57);
  static const Color outlineVariant = Color(0xFF32333E);

  // Expressive Accent Accents (For Genres, Moods, Playlists)
  static const Color accentViolet = Color(0xFF9E54FF);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentPink = Color(0xFFFF4081);
  static const Color accentOrange = Color(0xFFFF6E40);
  static const Color accentAmber = Color(0xFFFFB74D);
  static const Color accentBlue = Color(0xFF2979FF);
  static const Color accentEmerald = Color(0xFF00E676);
  static const Color accentRose = Color(0xFFE91E63);

  // Dynamic ColorScheme generator supporting dominant artwork seed
  static ColorScheme createColorScheme({
    Color primary = spotifyGreen,
    Brightness brightness = Brightness.dark,
  }) {
    if (brightness == Brightness.dark) {
      return ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: Colors.black,
        primaryContainer: primary.withAlpha(55),
        onPrimaryContainer: Colors.white,
        secondary: const Color(0xFF72D572),
        onSecondary: Colors.black,
        secondaryContainer: const Color(0xFF274E27),
        onSecondaryContainer: const Color(0xFFB5F2B5),
        tertiary: accentViolet,
        onTertiary: Colors.black,
        tertiaryContainer: accentViolet.withAlpha(55),
        onTertiaryContainer: const Color(0xFFEADBFF),
        error: const Color(0xFFFFB4AB),
        onError: const Color(0xFF690005),
        errorContainer: const Color(0xFF93000A),
        onErrorContainer: const Color(0xFFFFDAD6),
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        inverseSurface: const Color(0xFFE4E1E9),
        onInverseSurface: const Color(0xFF2F3036),
        inversePrimary: spotifyGreenDark,
        shadow: Colors.black,
      );
    } else {
      return ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      );
    }
  }
}
