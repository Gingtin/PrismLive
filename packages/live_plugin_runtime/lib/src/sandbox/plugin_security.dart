/// Security checks and domain whitelist validation for live plugins.
library;

/// Exception thrown when a plugin attempts an unauthorized operation.
class PluginSecurityException implements Exception {
  /// Creates a [PluginSecurityException].
  const new(this.message);

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'PluginSecurityException: $message';
}

/// Validates whether a target URL or domain is permitted by the plugin's manifest.
abstract final class DomainWhitelistValidator {
  /// Checks whether [uri] is permitted under [allowedDomains].
  ///
  /// Matching rules:
  /// - Exact domain match (e.g. `api.live.com` matches `api.live.com`).
  /// - Wildcard subdomain match (e.g. `*.live.com` or `.live.com` matches `sub.live.com` and `live.com`).
  /// - Suffix match if domain starts with a dot.
  static bool isAllowed(Uri uri, List<String> allowedDomains) {
    if (allowedDomains.isEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase().trim();
    if (host.isEmpty) {
      return false;
    }

    for (final domain in allowedDomains) {
      final clean = domain.toLowerCase().trim();
      if (clean == '*') {
        return true;
      }
      if (clean.startsWith('*.')) {
        final suffix = clean.substring(2);
        if (host == suffix || host.endsWith('.$suffix')) {
          return true;
        }
      } else if (clean.startsWith('.')) {
        final suffix = clean.substring(1);
        if (host == suffix || host.endsWith('.$suffix')) {
          return true;
        }
      } else {
        if (host == clean || host.endsWith('.$clean')) {
          return true;
        }
      }
    }

    return false;
  }

  /// Asserts that [uri] is permitted, throwing [PluginSecurityException] otherwise.
  static void assertAllowed(Uri uri, List<String> allowedDomains) {
    if (!isAllowed(uri, allowedDomains)) {
      throw PluginSecurityException(
        'Access to host "${uri.host}" is not permitted by plugin manifest allowedDomains: $allowedDomains',
      );
    }
  }
}
