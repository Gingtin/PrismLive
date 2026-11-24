import 'package:live_core/live_core.dart';
import 'package:live_plugin_runtime/src/manifest/plugin_manifest.dart';

/// Standard 4-method contract required for all NextGen PrismLive plugins.
abstract interface class PluginContract {
  /// 1. Returns static or dynamic platform metadata and capability descriptor.
  Future<PluginManifest> meta();

  /// 2. Returns live room details, streamer info, and broadcast status.
  Future<LiveRoom> getRoomInfo(String roomId);

  /// 3. Returns available play qualities with corresponding streaming lines.
  Future<List<LivePlayQuality>> getPlayQualities(String roomId);

  /// 4. Returns danmaku server configuration (websocket url, token, heartbeat, etc.).
  Future<Map<String, dynamic>> getDanmakuConfig(String roomId);
}
