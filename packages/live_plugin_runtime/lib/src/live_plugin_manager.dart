import 'dart:convert';
import 'dart:typed_data';

import 'package:live_net/live_net.dart';
import 'package:live_plugin_runtime/src/crypto/ed25519.dart';
import 'package:live_plugin_runtime/src/live_plugin.dart';
import 'package:live_plugin_runtime/src/manifest/plugin_manifest.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_host_api.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_sandbox.dart';
import 'package:live_plugin_runtime/src/sandbox/plugin_security.dart';

/// Central manager for loading, verifying, and maintaining live plugins.
class LivePluginManager {
  /// Creates a [LivePluginManager].
  new({
    LiveHttp? http,
    void Function(String message)? onLog,
  })  : _http = http ?? IoLiveHttp(),
        _onLog = onLog ?? ((_) {});

  final LiveHttp _http;
  final void Function(String message) _onLog;

  final Map<String, LivePluginSite> _installedPlugins = {};
  final Map<String, LivePluginSite> _fallbackCache = {};

  /// All currently active and verified plugin platform adapters.
  List<LivePluginSite> get installedSites => _installedPlugins.values.toList();

  /// Gets a verified plugin site by platform ID, or null if not installed.
  LivePluginSite? getSite(String id) => _installedPlugins[id.toLowerCase()];

  /// Loads, verifies, and activates a plugin from manifest and script source.
  ///
  /// If verification fails and an older verified version exists in cache,
  /// this method logs a security warning and safely retains the cached version.
  LivePluginSite loadPlugin({
    required PluginManifest manifest,
    required String script,
    bool verifySignature = true,
  }) {
    final hostApi = PluginHostApi(
      allowedDomains: manifest.allowedDomains,
      http: _http,
      onLog: _onLog,
    );

    try {
      final sandbox = PluginSandbox(
        manifest: manifest,
        script: script,
        hostApi: hostApi,
        verifySignature: verifySignature,
      );

      final site = LivePluginSite(sandbox);
      _installedPlugins[manifest.id.toLowerCase()] = site;
      _fallbackCache[manifest.id.toLowerCase()] = site;
      _onLog('Plugin "${manifest.id}" (v${manifest.version}) loaded & verified successfully.');
      return site;
    } on PluginSecurityException catch (e) {
      _onLog('SECURITY WARNING: Plugin "${manifest.id}" rejected: ${e.message}');
      final fallback = _fallbackCache[manifest.id.toLowerCase()];
      if (fallback != null) {
        _onLog('Falling back to previously verified version of "${manifest.id}".');
        _installedPlugins[manifest.id.toLowerCase()] = fallback;
        return fallback;
      }
      rethrow;
    }
  }

  /// Utility to sign a plugin script with a 64-byte secret key.
  static String signScript(String script, Uint8List secretKey) {
    final bytes = Uint8List.fromList(utf8.encode(script));
    final signature = Ed25519.sign(bytes, secretKey);
    return Ed25519.bytesToHex(signature);
  }
}
