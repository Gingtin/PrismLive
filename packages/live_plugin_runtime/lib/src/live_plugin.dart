import 'package:live_core/live_core.dart';
import 'package:live_plugin_runtime/src/manifest/plugin_manifest.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_sandbox.dart';

/// A dynamic platform adapter backed by a signed [PluginSandbox].
///
/// Implements [LiveSite] so the app, player, and patrol tools interact with it
/// identically to native platform adapters.
class LivePluginSite extends LiveSite {
  /// Creates a [LivePluginSite] wrapping [sandbox].
  new(this.sandbox);

  /// The underlying sandbox.
  final PluginSandbox sandbox;

  /// The plugin manifest.
  PluginManifest get manifest => sandbox.manifest;

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  SourceDescriptor get descriptor => manifest.toSourceDescriptor();

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    try {
      return await sandbox.getRoomInfo(roomId);
    } on Object catch (_) {
      return LiveRoom(
        roomId: roomId,
        platform: id,
        watching: '',
        liveStatus: LiveStatus.unknown,
      );
    }
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    try {
      return await sandbox.getPlayQualities(detail.roomId);
    } on Object catch (_) {
      return const [];
    }
  }

  @override
  Future<List<String>> getPlayUrls({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    if (quality.data is List<String>) {
      return quality.data! as List<String>;
    } else if (quality.data is List) {
      return (quality.data! as List).map((e) => e.toString()).toList();
    }

    final qualities = await getPlayQualities(detail: detail);
    for (final q in qualities) {
      if (q.selectionId == quality.selectionId || q.quality == quality.quality) {
        if (q.data is List<String>) {
          return q.data! as List<String>;
        } else if (q.data is List) {
          return (q.data! as List).map((e) => e.toString()).toList();
        }
      }
    }
    return const [];
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await getRoomDetail(roomId: roomId);
    return room.liveStatus == LiveStatus.live;
  }
}
