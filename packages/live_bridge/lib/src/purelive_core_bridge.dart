import 'dart:convert';
import 'dart:ffi';

import 'package:live_core/live_core.dart';
import 'package:live_bridge/src/bridge_bindings.dart';

/// PureLive Core Native Engine Bridge Singleton
final class PureLiveCoreBridge {
  PureLiveCoreBridge._(this._bindings);

  static PureLiveCoreBridge? _instance;

  final PureLiveCoreBindings _bindings;

  /// Whether the native engine is compiled and available on the current platform
  static bool get isAvailable => instance != null;

  /// Singleton instance, or null if native binary not loaded
  static PureLiveCoreBridge? get instance {
    if (_instance != null) return _instance;
    final bindings = PureLiveCoreBindings.load();
    if (bindings != null) {
      bindings.init();
      _instance = PureLiveCoreBridge._(bindings);
    }
    return _instance;
  }

  /// Version of the underlying Rust core engine
  String get version => _bindings.version;

  /// Spawns a Rust loopback relay server with the given proxy configuration
  RustRelayServer? createRelay({
    String? defaultProxy,
    Map<String, String>? siteProxies,
  }) {
    final proxyJson = jsonEncode({
      'default_proxy': defaultProxy,
      'site_proxies': siteProxies ?? const {},
    });

    final handle = _bindings.relayCreate(proxyJson);
    if (handle == nullptr) return null;

    final port = _bindings.relayGetPort(handle);
    return RustRelayServer._(_bindings, handle, port);
  }
}

/// Active Rust Native Loopback Relay Server Instance
final class RustRelayServer {
  RustRelayServer._(this._bindings, this._handle, this.port);

  final PureLiveCoreBindings _bindings;
  Pointer<Void> _handle;
  final int port;
  bool _isClosed = false;

  bool get isClosed => _isClosed;

  /// Registers an upstream live stream and returns a local loopback playback URL
  String? registerSession({
    required String sessionId,
    required String upstreamUrl,
    required String site,
    required NetworkMode networkMode,
    Map<String, String>? headers,
    bool isFlv = true,
  }) {
    if (_isClosed) return null;

    final configJson = jsonEncode({
      'session_id': sessionId,
      'upstream_url': upstreamUrl,
      'site': site,
      'network_mode': networkMode.name,
      'headers': headers ?? const {},
      'is_flv': isFlv,
    });

    return _bindings.relayRegisterSession(_handle, configJson);
  }

  /// Unregisters an upstream live session
  void unregisterSession(String sessionId) {
    if (_isClosed) return;
    _bindings.relayUnregisterSession(_handle, sessionId);
  }

  /// Starts concurrent zero-copy Stream Tee recording for an active session
  bool startRecord({
    required String sessionId,
    required String outputDir,
    required String filePrefix,
    int maxDurationSecs = 0,
    int maxBytes = 0,
  }) {
    if (_isClosed) return false;
    return _bindings.relayStartRecord(
      _handle,
      sessionId,
      outputDir,
      filePrefix,
      maxDurationSecs: maxDurationSecs,
      maxBytes: maxBytes,
    );
  }

  /// Stops recording for an active session
  bool stopRecord(String sessionId) {
    if (_isClosed) return false;
    return _bindings.relayStopRecord(_handle, sessionId);
  }

  /// Checks if a session is currently being recorded via Stream Tee
  bool isRecording(String sessionId) {
    if (_isClosed) return false;
    return _bindings.relayIsRecording(_handle, sessionId);
  }

  /// Shuts down the relay server
  void dispose() {
    if (_isClosed) return;
    _isClosed = true;
    _bindings.relayDestroy(_handle);
    _handle = nullptr;
  }
}
