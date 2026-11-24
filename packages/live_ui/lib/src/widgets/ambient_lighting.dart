import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/network_image.dart';

/// The physical pixel width used to decode stream covers for ambient lighting.
///
/// Kept tiny (32px) so hardware bilinear scaling generates a natural, silky
/// bokeh glow without incurring any expensive CPU or per-frame fragment shader cost.
const int ambientLightingDecodeWidth = 32;

/// A cinema-style ambient lighting layer (影院动态流光氛围背光).
///
/// Blown up behind the video player and letterbox margins, it bathes the screen
/// edges in the ambient colors of the current stream, fading smoothly into black
/// via an atmospheric vignette.
class AmbientLightingLayer extends StatelessWidget {
  /// Creates the ambient lighting layer for [cover].
  const new({
    required this.cover,
    this.intensity = 0.65,
    this.blurRadius = 40.0,
    super.key,
  });

  /// The room's cover or stream backdrop address (empty for fallback gradient).
  final String cover;

  /// Brightness / intensity of the ambient glow (0.1 to 1.0).
  final double intensity;

  /// Diffusion radius factor (10.0 to 80.0), mapped to scaling & vignette depth.
  final double blurRadius;

  @override
  Widget build(BuildContext context) {
    final url = cover.trim();
    final clampedIntensity = intensity.clamp(0.1, 1.0);
    // Map blurRadius (10..80) to scale factor (1.18..1.50)
    final scale = 1.18 + (blurRadius.clamp(10.0, 80.0) - 10.0) / 70.0 * 0.32;

    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          key: const ValueKey('ambient-lighting-layer'),
          fit: StackFit.expand,
          children: [
            // Deep black ground
            const ColoredBox(color: OnVideoColors.ground),
            // Fallback gradient in case image is missing or loading
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF342B3A).withValues(alpha: clampedIntensity * 0.7),
                    const Color(0xFF171B27).withValues(alpha: clampedIntensity * 0.7),
                    const Color(0xFF2A202B).withValues(alpha: clampedIntensity * 0.7),
                  ],
                ),
              ),
            ),
            if (url.isNotEmpty)
              Opacity(
                opacity: clampedIntensity,
                child: Transform.scale(
                  scale: scale,
                  child: LiveNetworkImage(
                    key: const ValueKey('ambient-lighting-cover'),
                    url: url,
                    memCacheWidth: ambientLightingDecodeWidth,
                    placeholder: (_) => const SizedBox.shrink(),
                    error: (_) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // Atmospheric cinema vignette: bright around center/video edges, fading softly to pure black at outer borders
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.15,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                  stops: const [0.35, 0.65, 0.88, 1.0],
                ),
              ),
            ),
            // Overall intensity dimmer veil
            ColoredBox(
              color: Colors.black.withValues(alpha: (1.0 - clampedIntensity) * 0.6),
            ),
          ],
        ),
      ),
    );
  }
}
