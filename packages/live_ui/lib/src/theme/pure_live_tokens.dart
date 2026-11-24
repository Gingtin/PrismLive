import 'dart:math' as math;
import 'package:flutter/material.dart';

/// StyleSeed 2.0 Semantic Design Tokens (PureLive 4.x+ NextGen Spec §4.1).
///
/// Encapsulates cinema-grade visual tokens, contrast clamping (WCAG AA/AAA),
/// and responsive layout metrics across Mobile, Desktop, and 10-Foot TV.
@immutable
final class PureLiveTokens extends ThemeExtension<PureLiveTokens> {
  /// Creates a tokens instance.
  const new({
    this.cardRadius = 12,
    this.cardSpacing = 8,
    this.cinemaSurface = const Color(0xFF0F0F14),
    this.accentColor = const Color(0xFF6750A4),
    this.hudScrim = const Color(0x99000000),
    this.hudBorderHighlight = const Color(0x26FFFFFF),
    this.animationFast = const Duration(milliseconds: 150),
    this.animationMedium = const Duration(milliseconds: 300),
  });

  /// Dark Cinema Mode (Default).
  static const darkCinema = PureLiveTokens(
    accentColor: Color(0xFFD0BCFF),
  );

  /// OLED True Black Mode (Maximum power saving and contrast).
  static const oledBlack = PureLiveTokens(
    cinemaSurface: Color(0xFF000000),
    accentColor: Color(0xFFD0BCFF),
    hudScrim: Color(0xCC000000),
    hudBorderHighlight: Color(0x33FFFFFF),
  );

  /// Clean Light Mode.
  static const cleanLight = PureLiveTokens(
    cinemaSurface: Color(0xFFF7F8FA),
    hudScrim: Color(0x66000000),
    hudBorderHighlight: Color(0x1F000000),
  );

  /// Border radius for cards and tiles.
  final double cardRadius;

  /// Spacing between grid cards.
  final double cardSpacing;

  /// Ground surface color (cinema dark or pure OLED black).
  final Color cinemaSurface;

  /// Primary theme accent color.
  final Color accentColor;

  /// Scrim overlay behind HUD controls.
  final Color hudScrim;

  /// 1px border highlight for non-blur glass HUDs.
  final Color hudBorderHighlight;

  /// Fast animation duration (150ms).
  final Duration animationFast;

  /// Medium animation duration (300ms).
  final Duration animationMedium;

  /// Clamps [foreground] brightness over [background] to strictly satisfy
  /// WCAG contrast ratio requirements (AA >= 4.5:1, AAA >= 7.0:1).
  static Color clampContrast(
    Color foreground,
    Color background, {
    double minRatio = 4.5,
  }) {
    double luminance(Color c) {
      double channel(double v) =>
          v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    }

    final bgL = luminance(background);
    double ratio(Color fg) {
      final fgL = luminance(fg);
      final l1 = math.max(fgL, bgL);
      final l2 = math.min(fgL, bgL);
      return (l1 + 0.05) / (l2 + 0.05);
    }

    if (ratio(foreground) >= minRatio) return foreground;

    // Prefer lightening for dark backgrounds, darkening for light backgrounds
    final shouldLighten = bgL < 0.5;
    var hsl = HSLColor.fromColor(foreground);

    for (var i = 0; i < 20; i++) {
      final newLightness = (shouldLighten ? hsl.lightness + 0.05 : hsl.lightness - 0.05).clamp(0, 1).toDouble();
      hsl = hsl.withLightness(newLightness);
      final candidate = hsl.toColor();
      if (ratio(candidate) >= minRatio) return candidate;
    }

    return shouldLighten ? Colors.white : Colors.black;
  }

  @override
  PureLiveTokens copyWith({
    double? cardRadius,
    double? cardSpacing,
    Color? cinemaSurface,
    Color? accentColor,
    Color? hudScrim,
    Color? hudBorderHighlight,
    Duration? animationFast,
    Duration? animationMedium,
  }) => PureLiveTokens(
    cardRadius: cardRadius ?? this.cardRadius,
    cardSpacing: cardSpacing ?? this.cardSpacing,
    cinemaSurface: cinemaSurface ?? this.cinemaSurface,
    accentColor: accentColor ?? this.accentColor,
    hudScrim: hudScrim ?? this.hudScrim,
    hudBorderHighlight: hudBorderHighlight ?? this.hudBorderHighlight,
    animationFast: animationFast ?? this.animationFast,
    animationMedium: animationMedium ?? this.animationMedium,
  );

  @override
  ThemeExtension<PureLiveTokens> lerp(ThemeExtension<PureLiveTokens>? other, double t) {
    if (other is! PureLiveTokens) return this;
    return PureLiveTokens(
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      cardSpacing: cardSpacing + (other.cardSpacing - cardSpacing) * t,
      cinemaSurface: Color.lerp(cinemaSurface, other.cinemaSurface, t)!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      hudScrim: Color.lerp(hudScrim, other.hudScrim, t)!,
      hudBorderHighlight: Color.lerp(hudBorderHighlight, other.hudBorderHighlight, t)!,
      animationFast: animationFast,
      animationMedium: animationMedium,
    );
  }
}
