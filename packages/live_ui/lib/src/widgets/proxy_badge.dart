import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

/// Network proxy requirement mode for UI rendering.
enum ProxyBadgeMode {
  /// Direct connection without proxy.
  direct('direct', '直连'),

  /// Proxy recommended for high bitrate or stability.
  proxyRecommended('proxyRecommended', '建议代理'),

  /// Domestic connection blocked or severely throttled; proxy required.
  proxyRequired('proxyRequired', '需代理');

  new(this.code, this.label);

  /// Mode code string.
  final String code;

  /// Display label.
  final String label;

  /// Whether a proxy is strictly required.
  bool get isRequired => this == ProxyBadgeMode.proxyRequired;

  /// Whether a proxy is recommended or required.
  bool get usesProxy => this != ProxyBadgeMode.direct;

  /// Parses from standard string code.
  static ProxyBadgeMode fromCode(String? code) {
    return switch (code?.toLowerCase()) {
      'proxyrequired' || 'required' => ProxyBadgeMode.proxyRequired,
      'proxyrecommended' || 'recommended' => ProxyBadgeMode.proxyRecommended,
      _ => ProxyBadgeMode.direct,
    };
  }
}

/// Visual badge representing a live source's network and proxy requirement
/// according to the NextGen Master Spec.
///
/// - [ProxyBadgeMode.direct]: no badge rendered (or compact green dot if requested).
/// - [ProxyBadgeMode.proxyRecommended]: amber earth/node badge ("建议代理").
/// - [ProxyBadgeMode.proxyRequired]: cobalt blue shield/VPN badge ("需代理").
class ProxyBadge extends StatelessWidget {
  /// Creates a [ProxyBadge].
  const new({
    required this.mode,
    super.key,
    this.compact = false,
    this.showDirect = false,
    this.onTap,
  });

  /// The proxy requirement mode.
  final ProxyBadgeMode mode;

  /// Whether to render a compact icon-only badge.
  final bool compact;

  /// Whether to show a badge even for direct connections (defaults to false).
  final bool showDirect;

  /// Optional tap handler (e.g. open platform proxy node selector).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (mode == ProxyBadgeMode.direct && !showDirect) {
      return const SizedBox.shrink();
    }

    final (color, icon, label) = switch (mode) {
      ProxyBadgeMode.direct => (
        const Color(0xFF10B981),
        Remix.flashlight_line,
        '直连',
      ),
      ProxyBadgeMode.proxyRecommended => (
        const Color(0xFFF59E0B), // Amber
        Remix.global_line,
        '建议代理',
      ),
      ProxyBadgeMode.proxyRequired => (
        const Color(0xFF2563EB), // Cobalt Blue
        Remix.shield_keyhole_line,
        '需代理',
      ),
    };

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 13, color: color),
          if (!compact) ...[
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );

    final tooltip = switch (mode) {
      ProxyBadgeMode.direct => '国内网络直连访问流畅',
      ProxyBadgeMode.proxyRecommended => '建议配置代理以保证高画质与低延迟稳定访问',
      ProxyBadgeMode.proxyRequired => '该平台国内网络受限，必须通过代理节点访问',
    };

    final badge = Tooltip(
      message: tooltip,
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
