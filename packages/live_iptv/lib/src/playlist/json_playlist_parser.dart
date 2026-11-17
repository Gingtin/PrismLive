import 'dart:convert';

import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/m3u_parser.dart';
import 'package:live_iptv/src/playlist/playlist_parse_result.dart';
import 'package:live_iptv/src/playlist/txt_parser.dart';
import 'package:live_net/live_net.dart';

/// Parses JSON playlists (TVBox live format, flat channel arrays, and group dictionaries).
///
/// Supported formats:
/// - TVBox `lives` structure: `{"lives": [{"group": "...", "channels": [{"name": "...", "urls": [...]}]}]}`
/// - Array of groups or channels: `[{"group": "...", "channels": [...]}]` or `[{"name": "...", "url": "..."}]`
/// - Root wrappers: `{"channels": [...]}`, `{"data": [...]}`, `{"list": [...]}`
/// - Group dictionaries: `{"央视频道": [{"name": "CCTV-1", "url": "..."}]}`
/// - Channels with multiple sources (array in `urls` or `#`-separated strings) are numbered as `(线路N)`.
final class JsonPlaylistParser {
  /// Creates a parser.
  const new();

  /// Default group for channels without a specified category.
  static const String defaultGroup = 'Uncategorized';

  /// URL schemes accepted in playlists.
  static const Set<String> schemes = {
    'http',
    'https',
    'rtmp',
    'rtsp',
    'rtp',
    'udp',
    'mms',
    'p2p',
  };

  /// Parses [content] as a JSON playlist.
  PlaylistParseResult parse(String content) {
    var raw = content.trim();
    if (raw.startsWith('\uFEFF')) {
      raw = raw.substring(1).trim();
    }
    if (raw.isEmpty) {
      return PlaylistParseResult(
        entries: const [],
        issues: const [PlaylistIssue(0, 'Playlist content is empty')],
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      return PlaylistParseResult(
        entries: const [],
        issues: [PlaylistIssue(0, 'Malformed JSON: ${e.message}')],
      );
    }

    final entries = <IptvEntry>[];
    final issues = <PlaylistIssue>[];

    void processChannel(Map<String, Object?> item, {String? group}) {
      final name = _text(item, const [
        'name',
        'channel_name',
        'channel',
        'title',
        'tvg-name',
        'tvgName',
        'tvg_name',
      ]);
      if (name == null ||
          name.isEmpty ||
          name.startsWith('—') ||
          name.startsWith('[') ||
          name.contains('更新时间') ||
          name.contains('提示')) {
        return;
      }

      final channelGroup = _text(item, const [
        'group',
        'group_name',
        'group_title',
        'groupTitle',
        'category',
        'genre',
      ]) ?? group ?? defaultGroup;

      final logo = _text(item, const ['logo', 'tvg-logo', 'tvgLogo', 'tvg_logo', 'icon', 'image']);
      final tvgId = _text(item, const ['tvg-id', 'tvgId', 'tvg_id', 'id']);
      final tvgName = _text(item, const ['tvg-name', 'tvgName', 'tvg_name']);
      final chnoStr = _text(item, const ['tvg-chno', 'tvgChno', 'chno', 'channelNumber', 'num', 'number']);
      final channelNumber = chnoStr != null ? int.tryParse(chnoStr) : null;

      final catchupMode = _text(item, const ['catchup', 'catchup-type', 'catchupType'])?.toLowerCase();
      final catchupSource = _text(item, const ['catchup-source', 'catchupSource']);
      final catchupDaysStr = _text(item, const ['catchup-days', 'catchupDays', 'timeshift', 'tvg-rec']);
      final catchupDays = catchupDaysStr != null ? double.tryParse(catchupDaysStr) : null;

      // Channel headers
      final channelHeaders = <String, String>{};
      final rawHeaders = item['headers'] ?? item['httpHeaders'] ?? item['header'];
      if (rawHeaders is Map) {
        for (final entry in rawHeaders.entries) {
          if (entry.key != null && entry.value != null) {
            channelHeaders[entry.key.toString()] = entry.value.toString();
          }
        }
      }

      // Collect raw url candidates
      final rawUrls = <String>[];
      final urlsField = item['urls'];
      if (urlsField is List) {
        for (final u in urlsField) {
          if (u is String) {
            rawUrls.add(u);
          } else if (u is Map<String, Object?>) {
            final subUrl = _text(u, const ['url', 'link', 'source', 'playUrl', 'streamUrl']);
            if (subUrl != null) rawUrls.add(subUrl);
          }
        }
      }
      final singleUrl = item['url'] ?? item['link'] ?? item['source'] ?? item['playUrl'] ?? item['streamUrl'];
      if (singleUrl is String) {
        rawUrls.add(singleUrl);
      } else if (singleUrl is List) {
        for (final u in singleUrl) {
          if (u is String) rawUrls.add(u);
        }
      }

      // Split '#' and validate schemes
      final validStreams = <({String url, Map<String, String> headers})>[];
      for (final rawUrl in rawUrls) {
        for (final part in rawUrl.split('#')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final parsedStream = _parseStreamUrl(trimmed);
          if (!isSupportedStreamUrl(parsedStream.url, schemes)) continue;
          final mergedHeaders = HttpHeaderPolicy.normalize({
            ...channelHeaders,
            ...parsedStream.headers,
          });
          validStreams.add((url: parsedStream.url, headers: mergedHeaders));
        }
      }

      var index = 1;
      for (final stream in validStreams) {
        final entryName = validStreams.length > 1 ? '$name (线路$index)' : name;
        entries.add(
          IptvEntry(
            name: entryName,
            streamUrl: stream.url,
            tvgId: tvgId != null && tvgId.isNotEmpty ? tvgId : null,
            tvgName: tvgName != null && tvgName.isNotEmpty ? tvgName : null,
            tvgLogo: logo != null && logo.isNotEmpty ? logo : null,
            groupTitle: channelGroup.isNotEmpty ? channelGroup : defaultGroup,
            channelNumber: channelNumber,
            streamType: _streamType(channelGroup, stream.url),
            catchupMode: catchupMode != null && catchupMode.isNotEmpty ? catchupMode : null,
            catchupSource: catchupSource != null && catchupSource.isNotEmpty ? catchupSource : null,
            catchupDays: catchupDays,
            httpHeaders: stream.headers,
          ),
        );
        index++;
      }
    }

    void processGroup(Object? groupObj, {String? defaultGroupName}) {
      if (groupObj is! Map<String, Object?>) return;
      final groupName = _text(groupObj, const ['group', 'group_name', 'name', 'category', 'title']) ?? defaultGroupName;
      final channelsList = groupObj['channels'] ?? groupObj['channel'] ?? groupObj['list'] ?? groupObj['items'];
      if (channelsList is List) {
        for (final ch in channelsList) {
          if (ch is Map<String, Object?>) {
            processChannel(ch, group: groupName);
          }
        }
      } else {
        processChannel(groupObj, group: groupName);
      }
    }

    if (decoded is Map<String, Object?>) {
      // Check for embedded text playlists
      final embeddedText = _text(decoded, const ['data', 'content', 'urls', 'channels_text']);
      if (embeddedText != null &&
          (embeddedText.startsWith('#EXTM3U') || embeddedText.contains(',#genre#'))) {
        return embeddedText.startsWith('#EXTM3U')
            ? const M3uParser().parse(embeddedText)
            : const TxtParser().parse(embeddedText);
      }

      final rootList = decoded['lives'] ??
          decoded['channels'] ??
          decoded['channel'] ??
          decoded['list'] ??
          decoded['items'] ??
          (decoded['data'] is List ? decoded['data'] : null);

      if (rootList is List) {
        for (final item in rootList) {
          if (item is Map<String, Object?>) {
            final hasSubList = item.containsKey('channels') ||
                item.containsKey('channel') ||
                item.containsKey('list') ||
                item.containsKey('items');
            if (hasSubList) {
              processGroup(item);
            } else {
              processChannel(item);
            }
          }
        }
      } else if (decoded['data'] is Map<String, Object?>) {
        final dataMap = decoded['data'] as Map<String, Object?>;
        for (final entry in dataMap.entries) {
          final val = entry.value;
          if (val is List) {
            for (final ch in val) {
              if (ch is Map<String, Object?>) {
                processChannel(ch, group: entry.key);
              }
            }
          }
        }
      } else {
        // Group dictionary: {"央视频道": [...], "卫视频道": [...]}
        for (final entry in decoded.entries) {
          final val = entry.value;
          if (val is List) {
            for (final ch in val) {
              if (ch is Map<String, Object?>) {
                processChannel(ch, group: entry.key);
              }
            }
          }
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, Object?>) {
          final hasSubList = item.containsKey('channels') ||
              item.containsKey('channel') ||
              item.containsKey('list') ||
              item.containsKey('items');
          if (hasSubList) {
            processGroup(item);
          } else {
            processChannel(item);
          }
        }
      }
    }

    return PlaylistParseResult(entries: entries, issues: issues);
  }

  static String? _text(Map<String, Object?> item, List<String> keys) {
    for (final key in keys) {
      if (item[key] case final value?) {
        final s = value.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  static ({String url, Map<String, String> headers}) _parseStreamUrl(String raw) {
    final separator = raw.indexOf('|');
    if (separator < 0) return (url: raw.trim(), headers: const {});
    final url = raw.substring(0, separator).trim();
    final options = raw.substring(separator + 1);
    if (url.isEmpty || options.trim().isEmpty) return (url: raw.trim(), headers: const {});
    final headers = <String, String>{};
    for (final option in options.split('&')) {
      final equals = option.indexOf('=');
      if (equals <= 0 || equals == option.length - 1) continue;
      try {
        final rawName = Uri.decodeQueryComponent(option.substring(0, equals).trim());
        final value = Uri.decodeQueryComponent(option.substring(equals + 1).trim());
        headers[rawName] = value;
      } catch (_) {}
    }
    return (url: url, headers: HttpHeaderPolicy.normalize(headers));
  }

  static IptvStreamType _streamType(String? group, String url) {
    final lowerGroup = group?.toLowerCase() ?? '';
    final lowerUrl = url.toLowerCase();
    if (lowerGroup.contains('vod') || lowerGroup.contains('movie') || lowerUrl.contains('/movie/')) {
      return IptvStreamType.vod;
    }
    if (lowerGroup.contains('series') || lowerUrl.contains('/series/')) return IptvStreamType.series;
    return IptvStreamType.live;
  }
}
