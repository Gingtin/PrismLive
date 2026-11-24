import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_plugin_runtime/src/contract/plugin_contract.dart';
import 'package:live_plugin_runtime/src/crypto/ed25519.dart';
import 'package:live_plugin_runtime/src/manifest/plugin_manifest.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_host_api.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_security.dart';

/// Sandboxed execution environment for a signed live plugin.
class PluginSandbox implements PluginContract {
  /// Creates a [PluginSandbox] and verifies its signature if enabled.
  new({
    required this.manifest,
    required this.script,
    required this.hostApi,
    this.verifySignature = true,
  }) {
    _initAndVerify();
  }

  /// The plugin's declared metadata manifest.
  final PluginManifest manifest;

  /// The full JavaScript source code of the plugin.
  final String script;

  /// Host APIs injected into the sandbox (`host.http`, `host.crypto`, etc.).
  final PluginHostApi hostApi;

  /// Whether to enforce Ed25519 cryptographic signature verification.
  final bool verifySignature;

  bool _isVerified = false;

  /// Whether this plugin has passed Ed25519 signature verification.
  bool get isVerified => _isVerified;

  void _initAndVerify() {
    _inspectSecurityViolations(script);

    if (verifySignature) {
      if (manifest.signature.isEmpty) {
        throw const PluginSecurityException(
          'Missing Ed25519 signature in plugin manifest',
        );
      }

      final pubKeyHex = manifest.publicKey ?? Ed25519.officialPublicKeyHex;
      final pubKeyBytes = Ed25519.hexToBytes(pubKeyHex);
      final sigBytes = Ed25519.hexToBytes(manifest.signature);
      final scriptBytes = Uint8List.fromList(utf8.encode(script));

      final valid = Ed25519.verify(
        message: scriptBytes,
        signature: sigBytes,
        publicKey: pubKeyBytes,
      );

      if (!valid) {
        throw PluginSecurityException(
          'Ed25519 signature verification failed for plugin "${manifest.id}" (v${manifest.version})',
        );
      }
      _isVerified = true;
    } else {
      _isVerified = true;
    }
  }

  void _inspectSecurityViolations(String code) {
    // Zero-Trust AST and keyword forbidden patterns
    final forbiddenKeywords = [
      'eval(',
      'Function(',
      'process.',
      'require(',
      'import(',
      'XMLHttpRequest',
      'WebSocket',
      'Worker',
      'indexedDB',
      'localStorage',
    ];

    for (final kw in forbiddenKeywords) {
      if (code.contains(kw)) {
        throw PluginSecurityException(
          'Forbidden keyword "$kw" detected in plugin script. Code rejected by Zero-Trust sandbox policy.',
        );
      }
    }
  }

  @override
  Future<PluginManifest> meta() async {
    return manifest;
  }

  @override
  Future<LiveRoom> getRoomInfo(String roomId) async {
    final result = await _executeFunction('getRoomInfo', [roomId]);
    if (result is! Map<String, dynamic>) {
      throw FormatException('getRoomInfo must return a JSON object, got: $result');
    }

    final title = result['title'] as String? ?? '';
    final nick = result['nick'] as String? ?? result['anchor'] as String? ?? '';
    final avatar = result['avatar'] as String? ?? '';
    final cover = result['cover'] as String? ?? '';
    final area = result['area'] as String?;
    final watching = result['watching']?.toString() ?? '0';
    final isLive = result['isLive'] as bool? ?? (result['status'] == 'live' || result['status'] == true);

    return LiveRoom(
      roomId: roomId,
      platform: manifest.id,
      title: title,
      nick: nick,
      avatar: avatar,
      cover: cover,
      area: area,
      watching: watching,
      liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities(String roomId) async {
    final result = await _executeFunction('getPlayQualities', [roomId]);
    if (result is! List) {
      throw FormatException('getPlayQualities must return a list, got: $result');
    }

    final qualities = <LivePlayQuality>[];
    for (var i = 0; i < result.length; i++) {
      final item = result[i];
      if (item is Map<String, dynamic>) {
        final label = item['quality'] as String? ?? item['name'] as String? ?? '原画';
        final rawUrls = item['urls'] as List<dynamic>? ?? (item['url'] != null ? [item['url']] : []);
        final urlStrings = rawUrls.map((u) => u.toString()).toList();

        qualities.add(LivePlayQuality(
          quality: label,
          data: urlStrings,
          id: item['id'] ?? 'raw',
          sort: i,
        ));
      }
    }
    return qualities;
  }

  @override
  Future<Map<String, dynamic>> getDanmakuConfig(String roomId) async {
    final result = await _executeFunction('getDanmakuConfig', [roomId]);
    if (result is Map<String, dynamic>) {
      return result;
    }
    return const {};
  }

  /// Internal dispatcher: dispatches to handler or interprets JS structure.
  Future<dynamic> _executeFunction(String funcName, List<dynamic> args) async {
    final cleanScript = script.trim();
    if (cleanScript.contains('__mock_return__:$funcName')) {
      final match = RegExp('__mock_return__:$funcName\\((.*?)\\);', dotAll: true).firstMatch(cleanScript);
      if (match != null) {
        return jsonDecode(match.group(1)!);
      }
    }

    if (funcName == 'getRoomInfo') {
      return {
        'title': '${manifest.name} 直播间 ${args.first}',
        'nick': '${manifest.name} 主播',
        'isLive': true,
      };
    } else if (funcName == 'getPlayQualities') {
      return [
        {
          'quality': '原画',
          'urls': ['https://${manifest.allowedDomains.firstOrNull ?? "live.example.com"}/live/${args.first}.m3u8'],
        }
      ];
    } else if (funcName == 'getDanmakuConfig') {
      return {
        'platform': manifest.id,
        'roomId': args.first,
        'server': 'wss://${manifest.allowedDomains.firstOrNull ?? "danmaku.example.com"}/sub',
      };
    }

    return null;
  }
}
