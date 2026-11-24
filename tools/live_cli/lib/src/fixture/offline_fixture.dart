import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// Offline fixture store for live platform mock responses.
@immutable
class OfflineFixtureStore {
  /// Creates an [OfflineFixtureStore] reading from [directoryPath].
  const new([this.directoryPath = 'fixtures']);

  /// Directory containing JSON fixture files.
  final String directoryPath;

  File? _findFixtureFile(String platform) {
    final fileName = '${platform.toLowerCase()}_room.json';
    final candidates = [
      '$directoryPath/$fileName',
      'tools/live_cli/$directoryPath/$fileName',
      'tools/live_cli/fixtures/$fileName',
      'fixtures/$fileName',
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  /// Loads fixture JSON for [platform], or null if missing.
  Map<String, dynamic>? loadPlatformFixture(String platform) {
    final file = _findFixtureFile(platform);
    if (file == null) {
      return null;
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Parses fixture into a [LiveRoom] instance.
  LiveRoom? getRoom(String platform) {
    final data = loadPlatformFixture(platform);
    if (data == null) return null;

    final roomId = data['roomId'] as String? ?? '0';
    final title = data['title'] as String? ?? '';
    final nick = data['nick'] as String? ?? '';
    final avatar = data['avatar'] as String? ?? '';
    final cover = data['cover'] as String? ?? '';
    final watching = data['watching']?.toString() ?? '0';
    final isLive = data['liveStatus'] == 'live';

    return LiveRoom(
      roomId: roomId,
      platform: platform,
      title: title,
      nick: nick,
      avatar: avatar,
      cover: cover,
      watching: watching,
      liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
    );
  }

  /// Parses fixture into a list of [LivePlayQuality].
  List<LivePlayQuality> getQualities(String platform) {
    final data = loadPlatformFixture(platform);
    if (data == null) return const [];

    final rawQualities = data['qualities'] as List<dynamic>? ?? [];
    final result = <LivePlayQuality>[];

    for (var i = 0; i < rawQualities.length; i++) {
      final q = rawQualities[i] as Map<String, dynamic>;
      final qualityName = q['quality'] as String? ?? '原画';
      final urls = (q['urls'] as List<dynamic>? ?? []).map((u) => u.toString()).toList();
      final codec = q['codec'] as String?;

      result.add(LivePlayQuality(
        quality: qualityName,
        data: urls,
        id: qualityName,
        sort: i,
        codec: codec,
      ));
    }
    return result;
  }
}
