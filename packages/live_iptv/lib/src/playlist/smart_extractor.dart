import 'package:meta/meta.dart';

/// A source extracted from unstructured or structured text (e.g. `偶遇::http://...`).
@immutable
final class ExtractedSource {
  /// Creates an extracted source.
  const new({
    required this.name,
    required this.url,
    this.group,
    this.raw = '',
  });

  /// Name of the channel or subscription list.
  final String name;

  /// Web or stream address.
  final String url;

  /// Optional group/category name.
  final String? group;

  /// Raw input line or segment before extraction.
  final String raw;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractedSource &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          url == other.url &&
          group == other.group;

  @override
  int get hashCode => Object.hash(name, url, group);

  @override
  String toString() => '$name::$url';
}

/// Utility for extracting IPTV subscription links and stream URLs from messy,
/// multi-line clipboard or shared text.
///
/// Handles common community formats:
/// - `名称::http://...` or `名称:::http://...`
/// - `名称,http://...` or `名称，http://...`
/// - `名称|http://...`
/// - `名称$http://...` or `名称#http://...`
/// - `名称 http://...` (whitespace separator)
/// - `【名称】http://...` or `[名称](http://...)`
/// - Plain URLs (names derived from path basename)
final class IptvSmartExtractor {
  /// Creates an extractor.
  const new();

  static final RegExp _urlRegex = RegExp(
    r'(?:https?|rtmp|rtsp|rtp|udp|mms|p2p)://[^\s"<>]+',
    caseSensitive: false,
  );

  static final RegExp _leadingBulletRegex = RegExp(
    r'^[\s\-_*•·>]*(\d+[\.\、\:\)\-\s]+|\[\d+\]\s*|\(\d+\)\s*)?',
  );

  /// Extracts all [ExtractedSource] entries found within [text].
  static List<ExtractedSource> extract(String text) {
    if (text.trim().isEmpty) return const [];

    final lines = text.split(RegExp(r'\r?\n'));
    final results = <ExtractedSource>[];
    final seenUrls = <String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#') && !trimmed.contains('://')) continue;

      final extractedInLine = _extractFromLine(trimmed);
      for (final item in extractedInLine) {
        if (!seenUrls.contains(item.url)) {
          seenUrls.add(item.url);
          results.add(item);
        }
      }
    }

    // If newline splitting didn't find anything, try regex search over the whole block
    if (results.isEmpty) {
      for (final match in _urlRegex.allMatches(text)) {
        final url = match.group(0)!;
        if (!seenUrls.contains(url)) {
          seenUrls.add(url);
          results.add(ExtractedSource(name: _deriveNameFromUrl(url), url: url));
        }
      }
    }

    return results;
  }

  /// Extracts the first [ExtractedSource] from [text], or null if none found.
  static ExtractedSource? extractSingle(String text) {
    final list = extract(text);
    return list.isEmpty ? null : list.first;
  }

  /// Whether [text] contains at least 2 extracted sources.
  static bool hasMultipleSources(String text) => extract(text).length > 1;

  static List<ExtractedSource> _extractFromLine(String line) {
    final matches = _urlRegex.allMatches(line).toList();
    if (matches.isEmpty) return const [];

    final items = <ExtractedSource>[];

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final url = match.group(0)!.trim();
      final startIndex = match.start;
      final precedingText = line.substring(
        i == 0 ? 0 : matches[i - 1].end,
        startIndex,
      );

      final name = _cleanName(precedingText, fallbackUrl: url);
      items.add(ExtractedSource(name: name, url: url, raw: line));
    }

    return items;
  }

  static String _cleanName(String raw, {required String fallbackUrl}) {
    var name = raw.trim();

    // Strip leading numbering: e.g. "01.", "1、", "[1]", "- "
    name = name.replaceFirst(_leadingBulletRegex, '').trim();

    // Remove delimiters at the end of the name: "::", ":", ",", "，", "|", "$", "#", "="
    name = name.replaceAll(RegExp(r'[:：,，\|\$#=\s]+$'), '').trim();

    // Handle bracketed names: "【偶遇】" or "[偶遇]" or "（偶遇）"
    final bracketMatch = RegExp(r'^[\s【\[\(（]([^\s】\]\)）]+)[\s】\]\)）]').firstMatch(name);
    if (bracketMatch != null) {
      name = bracketMatch.group(1)!.trim();
    }

    // Strip any remaining surrounding quotes
    if (name.length > 1 &&
        ((name.startsWith('"') && name.endsWith('"')) ||
            (name.startsWith("'") && name.endsWith("'")))) {
      name = name.substring(1, name.length - 1).trim();
    }

    if (name.isEmpty) {
      return _deriveNameFromUrl(fallbackUrl);
    }

    return name;
  }

  static String _deriveNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Live';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      var last = segments.last;
      final dot = last.lastIndexOf('.');
      if (dot > 0) last = last.substring(0, dot);
      if (last.isNotEmpty) return last;
    }
    return uri.host.isNotEmpty ? uri.host : 'Live';
  }
}
