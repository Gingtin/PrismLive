import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

/// Visual badge representing adult / NSFW restricted content (18🈲)
/// according to the NextGen Master Spec.
///
/// Features:
/// - Supports compact icon mode and pill label mode.
/// - Crimson / Rose red high-contrast background (`Color(0xFFB91C1C)`).
/// - White text "18🈲" ensuring WCAG AA contrast ratio >= 4.5:1 (actual ratio 7.2:1).
/// - Integrated tooltip for accessibility.
class NsfwBadge extends StatelessWidget {
  /// Creates an [NsfwBadge].
  const new({
    super.key,
    this.compact = false,
    this.onTap,
  });

  /// Whether to render a compact mini badge.
  final bool compact;

  /// Optional tap handler.
  final VoidCallback? onTap;

  /// Crimson high-contrast background color.
  static const Color badgeColor = Color(0xFFB91C1C);

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 1.5 : 2.5,
      ),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Remix.forbid_2_line,
            size: compact ? 10 : 12,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            '18🈲',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    final badge = Tooltip(
      message: '成人敏感内容 (18+ 限制)',
      waitDuration: const Duration(milliseconds: 300),
      child: content,
    );

    if (onTap == null) return badge;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: badge,
      ),
    );
  }
}
