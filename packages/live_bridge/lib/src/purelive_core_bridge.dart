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

  /// Creates a real-time danmaku deduplication filter
  DanmakuFilter createDanmakuFilter({int capacity = 256, int threshold = 3}) {
    final handle = _bindings.danmakuFilterCreate(capacity, threshold);
    return DanmakuFilter._native(_bindings, handle);
  }
}

/// Computes 64-bit SimHash of [text] using native Rust or Dart fallback.
int computeSimHash64(String text) {
  final bridge = PureLiveCoreBridge.instance;
  if (bridge != null) {
    return bridge._bindings.computeSimHash64(text);
  }
  return _dartSimHash64(text);
}

/// Computes Hamming distance between two 64-bit fingerprints.
int hammingDistance(int h1, int h2) {
  final bridge = PureLiveCoreBridge.instance;
  if (bridge != null) {
    return bridge._bindings.hammingDistance(h1, h2);
  }
  return (h1 ^ h2).toRadixString(2).replaceAll('0', '').length;
}

/// Real-time danmaku deduplication filter
final class DanmakuFilter {
  DanmakuFilter._native(this._bindings, this._handle)
      : _capacity = 256,
        _threshold = 3;

  /// Creates a real-time danmaku deduplication filter, automatically using
  /// the native Rust implementation if available, or falling back to pure Dart.
  factory DanmakuFilter({int capacity = 256, int threshold = 3}) {
    final bridge = PureLiveCoreBridge.instance;
    if (bridge != null) {
      return bridge.createDanmakuFilter(capacity: capacity, threshold: threshold);
    }
    return DanmakuFilter._fallbackOnly(capacity, threshold);
  }

  /// Creates a fallback pure Dart filter
  factory DanmakuFilter.fallback({int capacity = 256, int threshold = 3}) =>
      DanmakuFilter(capacity: capacity, threshold: threshold);

  DanmakuFilter._fallbackOnly(this._capacity, this._threshold)
      : _bindings = null,
        _handle = null;

  final PureLiveCoreBindings? _bindings;
  Pointer<Void>? _handle;
  final int _capacity;
  final int _threshold;
  final List<int> _fallbackWindow = [];

  /// Resets the sliding window history.
  void reset() {
    _fallbackWindow.clear();
    final handle = _handle;
    final bindings = _bindings;
    if (handle != null && bindings != null) {
      bindings.danmakuFilterFree(handle);
      _handle = bindings.danmakuFilterCreate(_capacity, _threshold);
    }
  }

  /// Checks if [text] is a near-duplicate within the recent sliding window.
  bool isDuplicate(String text) {
    final handle = _handle;
    final bindings = _bindings;
    if (handle != null && bindings != null) {
      return bindings.danmakuFilterIsDuplicate(handle, text);
    }
    final hash = _dartSimHash64(text);
    for (final existing in _fallbackWindow) {
      if (hammingDistance(hash, existing) <= _threshold) {
        return true;
      }
    }
    if (_fallbackWindow.length >= _capacity) {
      _fallbackWindow.removeAt(0);
    }
    _fallbackWindow.add(hash);
    return false;
  }

  /// Disposes resources allocated by the filter
  void dispose() {
    final handle = _handle;
    final bindings = _bindings;
    if (handle != null && bindings != null) {
      bindings.danmakuFilterFree(handle);
      _handle = null;
    }
    _fallbackWindow.clear();
  }
}

int _dartSimHash64(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return 0;
  final runes = clean.runes.toList();
  if (runes.length == 1) return runes.first;

  final v = List<int>.filled(64, 0);
  for (var i = 0; i < runes.length - 1; i++) {
    final s = String.fromCharCodes([runes[i], runes[i + 1]]);
    final h = _fnv1a64(utf8.encode(s));
    for (var bit = 0; bit < 64; bit++) {
      if (((h >> bit) & 1) == 1) {
        v[bit]++;
      } else {
        v[bit]--;
      }
    }
  }

  var fingerprint = 0;
  for (var bit = 0; bit < 64; bit++) {
    if (v[bit] > 0) {
      fingerprint |= 1 << bit;
    }
  }
  return fingerprint;
}

int _fnv1a64(List<int> bytes) {
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask64 = (BigInt.one << 64) - BigInt.one;
  for (final b in bytes) {
    hash = (hash ^ BigInt.from(b)) & mask64;
    hash = (hash * prime) & mask64;
  }
  return hash.toSigned(64).toInt();
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
