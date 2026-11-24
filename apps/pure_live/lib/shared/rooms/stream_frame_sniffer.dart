import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';

/// Background sniffer that captures real-time video snapshots for visible
/// live streams (such as IPTV FLV streams) and stores them in [RealtimeCoverCache].
///
/// Features:
/// - Strictly single-worker serial queue (concurrency = 1) to avoid CPU/RAM overhead.
/// - 100% silent audio output (`ao: 'null'`, `volume: 0`).
/// - 3.5s per-stream timeout.
/// - Bounded visible queue: only the most recently requested visible cards (max 4)
///   are processed. Old cards that scrolled off are discarded.
/// - Automatic idle shutdown after 8 seconds to release player resources.
final class StreamFrameSniffer {
  new _();

  /// The singleton instance.
  static final StreamFrameSniffer instance = StreamFrameSniffer._();

  final List<LiveRoom> _queue = [];
  final Set<String> _failed = {};
  bool _running = false;
  bool _paused = false;
  MpvEngine? _engine;
  Timer? _idleTimer;

  /// Whether the sniffer is paused (e.g. while watching a live room in player).
  bool get isPaused => _paused;

  /// Pauses sniffing (call when entering full player page).
  void pause() {
    _paused = true;
    _queue.clear();
  }

  /// Resumes sniffing (call when returning to browse grid).
  void resume() {
    _paused = false;
  }

  /// Requests a real-time video snapshot for [room].
  ///
  /// Safe to call multiple times from visible card builders.
  void request(LiveRoom room) {
    if (_paused) {
      debugPrint('[StreamFrameSniffer] request skipped: paused');
      return;
    }
    final key = room.identityKey;
    final rawData = room.data;
    final data = rawData is String ? rawData.trim() : '';
    debugPrint('[StreamFrameSniffer] request: ${room.nick} key=$key data=$data');
    if (key.isEmpty || data.isEmpty) return;
    if (RealtimeCoverCache.get(key) != null) return;
    if (_failed.contains(key)) return;

    // Check if the URL is an HTTP/HTTPS stream
    final uri = Uri.tryParse(data);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    _queue.removeWhere((r) => r.identityKey == key);
    _queue.insert(0, room);
    if (_queue.length > 4) {
      _queue.removeRange(4, _queue.length);
    }

    _idleTimer?.cancel();
    _idleTimer = null;
    unawaited(_processQueue());
  }

  /// Clears the failure blacklist (e.g. after pull-to-refresh).
  void clearFailures() {
    _failed.clear();
  }

  Future<void> _processQueue() async {
    if (_running || _paused) return;
    if (_queue.isEmpty) {
      _scheduleIdleDispose();
      return;
    }

    _running = true;
    final room = _queue.removeAt(0);

    try {
      if (RealtimeCoverCache.get(room.identityKey) == null) {
        await _sniff(room);
      }
    } on Object catch (_) {
      _failed.add(room.identityKey);
    } finally {
      _running = false;
      if (_queue.isNotEmpty && !_paused) {
        unawaited(_processQueue());
      } else {
        _scheduleIdleDispose();
      }
    }
  }

  Future<void> _sniff(LiveRoom room) async {
    final rawData = room.data;
    final streamUrl = rawData is String ? rawData.trim() : '';
    final uri = Uri.tryParse(streamUrl);
    if (uri == null) return;

    debugPrint('[StreamFrameSniffer] sniffing: ${room.nick} url=$streamUrl');
    final engine = await _ensureEngine();
    if (engine == null) {
      debugPrint('[StreamFrameSniffer] engine creation failed');
      return;
    }

    final frameCompleter = Completer<void>();
    StreamSubscription<Object?>? sub;

    try {
      sub = engine.player.stream.videoParams.listen((params) {
        debugPrint('[StreamFrameSniffer] videoParams: ${room.nick} w=${params.w} h=${params.h}');
        if ((params.w ?? 0) > 0 && !frameCompleter.isCompleted) {
          frameCompleter.complete();
        }
      });

      await engine.open(
        EngineMedia(
          uri: uri,
          start: Duration.zero,
          decoder: DecoderMode.software,
        ),
      );

      await frameCompleter.future.timeout(const Duration(milliseconds: 3500));

      Uint8List? bytes;
      for (var attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 300 : 350));
        bytes = await engine.captureFrame();
        if (bytes != null && bytes.isNotEmpty) break;
      }

      debugPrint('[StreamFrameSniffer] captured bytes=${bytes?.length} for ${room.nick}');
      if (bytes != null && bytes.isNotEmpty) {
        RealtimeCoverCache.put(room.identityKey, bytes);
      } else {
        _failed.add(room.identityKey);
      }
    } on TimeoutException {
      debugPrint('[StreamFrameSniffer] timeout for ${room.nick}');
      _failed.add(room.identityKey);
    } on Object catch (e) {
      debugPrint('[StreamFrameSniffer] error for ${room.nick}: $e');
      _failed.add(room.identityKey);
    } finally {
      await sub?.cancel();
      try {
        await engine.player.stop().timeout(const Duration(milliseconds: 1000));
      } on Object catch (_) {}
    }
  }

  Future<MpvEngine?> _ensureEngine() async {
    if (_engine != null) return _engine;
    try {
      return _engine = await MpvEngine.create(
        config: MpvEngineConfig(
          audioOutputDriver: 'null',
          hardwareDecoding: false,
          liveBufferProfile: 'ultra_low',
          platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.android,
        ),
      );
    } on Object catch (_) {
      return null;
    }
  }

  void _scheduleIdleDispose() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 8), () async {
      final engine = _engine;
      _engine = null;
      if (engine != null) {
        try {
          await engine.dispose().timeout(const Duration(milliseconds: 2000));
        } on Object catch (_) {}
      }
    });
  }

  /// Disposes everything immediately.
  Future<void> dispose() async {
    _paused = true;
    _idleTimer?.cancel();
    _queue.clear();
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } on Object catch (_) {}
    }
  }
}
