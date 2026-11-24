import 'package:live_core/live_core.dart';
import 'package:live_plugin_runtime/src/crypto/ed25519.dart';
import 'package:meta/meta.dart';

/// Manifest specification for an external or dynamic live plugin.
@immutable
class PluginManifest {
  /// Creates a [PluginManifest].
  const new({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    this.description,
    this.allowedDomains = const [],
    this.signature = '',
    this.publicKey,
    this.region = SourceRegion.domestic,
    this.categories = const {SourceCategory.entertainment},
    this.networkMode = NetworkMode.direct,
    this.isNsfw = false,
    this.entryPoint = 'index.js',
    this.websiteUrl,
    this.aliases = const [],
  });

  /// Deserializes a manifest from JSON map.
  factory fromJson(Map<String, dynamic> json) {
    final regionStr = json['region'] as String? ?? 'domestic';
    final region = SourceRegion.values.firstWhere(
      (r) => r.code == regionStr,
      orElse: () => SourceRegion.domestic,
    );

    final rawCategories = json['categories'] as List<dynamic>? ?? ['entertainment'];
    final categories = rawCategories
        .map((c) => SourceCategory.values.firstWhere(
              (cat) => cat.code == c.toString(),
              orElse: () => SourceCategory.entertainment,
            ))
        .toSet();

    final networkModeStr = json['networkMode'] as String? ?? 'direct';
    final networkMode = NetworkMode.values.firstWhere(
      (m) => m.code == networkModeStr,
      orElse: () => NetworkMode.direct,
    );

    final rawDomains = json['allowedDomains'] as List<dynamic>? ?? [];
    final allowedDomains = rawDomains.map((d) => d.toString().toLowerCase()).toList();

    final rawAliases = json['aliases'] as List<dynamic>? ?? [];
    final aliases = rawAliases.map((a) => a.toString()).toList();

    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Community',
      description: json['description'] as String?,
      allowedDomains: allowedDomains,
      signature: json['signature'] as String? ?? '',
      publicKey: json['publicKey'] as String? ?? Ed25519.officialPublicKeyHex,
      region: region,
      categories: categories,
      networkMode: networkMode,
      isNsfw: json['isNsfw'] as bool? ?? false,
      entryPoint: json['entryPoint'] as String? ?? 'index.js',
      websiteUrl: json['websiteUrl'] as String?,
      aliases: aliases,
    );
  }

  /// Unique identifier of the plugin/platform.
  final String id;

  /// Display name of the plugin/platform.
  final String name;

  /// Semantic version string.
  final String version;

  /// Plugin author or maintainer organization.
  final String author;

  /// Optional human-readable description.
  final String? description;

  /// Whitelist of domain names that `host.http` is permitted to access.
  final List<String> allowedDomains;

  /// Ed25519 signature of the bundle script in hex format.
  final String signature;

  /// Public key used to verify the signature in hex format.
  final String? publicKey;

  /// Geographical region.
  final SourceRegion region;

  /// Category tags.
  final Set<SourceCategory> categories;

  /// Network proxy requirement mode.
  final NetworkMode networkMode;

  /// Whether the plugin serves adult/NSFW content.
  final bool isNsfw;

  /// Bundle entrypoint filename.
  final String entryPoint;

  /// Official website URL.
  final String? websiteUrl;

  /// Keyword aliases for search.
  final List<String> aliases;

  /// Converts this manifest into a strongly-typed [SourceDescriptor].
  SourceDescriptor toSourceDescriptor({
    SourceSupportStatus supportStatus = SourceSupportStatus.ready,
  }) {
    return SourceDescriptor(
      id: id,
      name: name,
      region: region,
      categories: categories,
      networkMode: networkMode,
      supportStatus: supportStatus,
      isNsfw: isNsfw,
      websiteUrl: websiteUrl,
      description: description,
      aliases: aliases,
    );
  }

  /// Serializes to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      if (description != null) 'description': description,
      'allowedDomains': allowedDomains,
      'signature': signature,
      if (publicKey != null) 'publicKey': publicKey,
      'region': region.code,
      'categories': categories.map((c) => c.code).toList(),
      'networkMode': networkMode.code,
      'isNsfw': isNsfw,
      'entryPoint': entryPoint,
      if (websiteUrl != null) 'websiteUrl': websiteUrl,
      'aliases': aliases,
    };
  }
}
