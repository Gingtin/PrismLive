/// Source descriptor and metadata contracts for live platforms, IPTV sources
/// and plugins according to the NextGen Master Spec.
library;

import 'package:meta/meta.dart';

/// Region of the live source.
enum SourceRegion {
  /// Mainland China.
  domestic('domestic', '国内'),

  /// International (US/Europe/Global).
  international('international', '国际'),

  /// East Asia (Japan/South Korea/Taiwan/Hong Kong).
  eastAsia('eastAsia', '日韩'),

  /// Southeast Asia.
  southeastAsia('southeastAsia', '东南亚'),

  /// Other or global unclassified.
  other('other', '其他');

  new(this.code, this.label);

  /// Region code string.
  final String code;

  /// Chinese display label.
  final String label;
}

/// Category tags of the live source.
enum SourceCategory {
  /// Gaming and Esports.
  game('game', '游戏电竞'),

  /// Entertainment and variety shows.
  entertainment('entertainment', '泛娱乐'),

  /// Voice chat, radio, ASMR and audio streams.
  audio('audio', '语音电台'),

  /// Sports live and racing.
  sports('sports', '体育赛事'),

  /// Free Ad-supported Streaming TV / Public Broadcasting.
  fastTv('fastTv', '电视广播'),

  /// News and current affairs.
  news('news', '综合新闻'),

  /// Lifestyle, vlog and live e-commerce.
  lifestyle('lifestyle', '生活日常'),

  /// Adult/NSFW (strictly isolated).
  adult('adult', '成人内容');

  new(this.code, this.label);

  /// Category code string.
  final String code;

  /// Chinese display label.
  final String label;
}

/// Network proxy requirement mode of the source.
enum NetworkMode {
  /// Direct connection without proxy.
  direct('direct', '直连'),

  /// Proxy recommended for high bitrate or stability, but direct works.
  proxyRecommended('proxyRecommended', '建议代理'),

  /// Domestic direct connection blocked or severely throttled; proxy required.
  proxyRequired('proxyRequired', '需代理');

  new(this.code, this.label);

  /// Mode code string.
  final String code;

  /// Display label.
  final String label;

  /// Whether a proxy is strictly required.
  bool get isRequired => this == NetworkMode.proxyRequired;

  /// Whether a proxy is recommended or required.
  bool get usesProxy => this != NetworkMode.direct;
}

/// Metadata descriptor for a live platform, IPTV feed, or custom plugin.
@immutable
class SourceDescriptor {
  /// Creates a [SourceDescriptor].
  const new({
    required this.id,
    required this.name,
    required this.region,
    required this.categories,
    required this.networkMode,
    this.isNsfw = false,
    this.isNative = false,
    this.websiteUrl,
    this.description,
    this.aliases = const [],
  });

  /// Generates a fallback descriptor when none is explicitly provided.
  factory fallback({
    required String id,
    required String name,
    SourceRegion region = SourceRegion.domestic,
    Set<SourceCategory> categories = const {SourceCategory.entertainment},
    NetworkMode networkMode = NetworkMode.direct,
    bool isNsfw = false,
  }) {
    return SourceDescriptor(
      id: id,
      name: name,
      region: region,
      categories: categories,
      networkMode: networkMode,
      isNsfw: isNsfw,
    );
  }

  /// Unique platform or source identifier (e.g. `bilibili`, `douyu`, `twitch`).
  final String id;

  /// Display name (e.g. `哔哩哔哩`, `斗鱼`, `Twitch`).
  final String name;

  /// Geographical origin of the source.
  final SourceRegion region;

  /// Multi-dimensional category classification tags.
  final Set<SourceCategory> categories;

  /// Network routing & proxy requirement.
  final NetworkMode networkMode;

  /// Whether this source is strictly categorized as NSFW (Adult Content).
  /// Under Hard Invariant #5, NSFW sources must be 100% hidden by default.
  final bool isNsfw;

  /// Whether this is a Core Native implemented source (vs Sandbox Plugin).
  final bool isNative;

  /// Official website URL.
  final String? websiteUrl;

  /// Brief description or technical notes.
  final String? description;

  /// Alias keywords and search shortcuts (including pinyin acronyms).
  final List<String> aliases;

  /// Whether this source matches the given search query [q]
  /// against id, name, aliases and pinyin acronyms.
  bool matchesQuery(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return true;
    if (id.toLowerCase().contains(query)) return true;
    if (name.toLowerCase().contains(query)) return true;
    for (final alias in aliases) {
      if (alias.toLowerCase().contains(query)) return true;
    }
    return false;
  }

  /// Creates a copy with specified fields replaced.
  SourceDescriptor copyWith({
    String? id,
    String? name,
    SourceRegion? region,
    Set<SourceCategory>? categories,
    NetworkMode? networkMode,
    bool? isNsfw,
    bool? isNative,
    String? websiteUrl,
    String? description,
    List<String>? aliases,
  }) {
    return SourceDescriptor(
      id: id ?? this.id,
      name: name ?? this.name,
      region: region ?? this.region,
      categories: categories ?? this.categories,
      networkMode: networkMode ?? this.networkMode,
      isNsfw: isNsfw ?? this.isNsfw,
      isNative: isNative ?? this.isNative,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      description: description ?? this.description,
      aliases: aliases ?? this.aliases,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          networkMode == other.networkMode &&
          isNsfw == other.isNsfw;

  @override
  int get hashCode => Object.hash(id, networkMode, isNsfw);

  @override
  String toString() => 'SourceDescriptor($id, $name, $region, $networkMode, nsfw=$isNsfw)';
}
