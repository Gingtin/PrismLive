import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Shows the speed test & stream health probe dialog for [playlist].
Future<void> showIptvSpeedTestDialog(
  BuildContext context, {
  required IptvPlaylist playlist,
  required IptvLibrary library,
  required LiveHttp http,
}) => showAppDialog<void>(
  context: context,
  wide: true,
  autofocus: false,
  builder: (_) => IptvSpeedTestDialog(
    playlist: playlist,
    library: library,
    http: http,
  ),
);

/// Interactive speed test dialog for IPTV channels.
class IptvSpeedTestDialog extends StatefulWidget {
  /// Creates the dialog.
  const IptvSpeedTestDialog({
    required this.playlist,
    required this.library,
    required this.http,
    super.key,
  });

  /// The playlist being tested.
  final IptvPlaylist playlist;

  /// Database storage for channels.
  final IptvLibrary library;

  /// HTTP client for stream probes.
  final LiveHttp http;

  @override
  State<IptvSpeedTestDialog> createState() => _IptvSpeedTestDialogState();
}

class _IptvSpeedTestDialogState extends State<IptvSpeedTestDialog> {
  List<IptvChannel>? _channels;
  bool _loadingChannels = true;
  bool _running = false;
  bool _done = false;
  CancelToken? _cancelToken;

  int _completed = 0;
  int _total = 0;
  int _liveCount = 0;
  int _offlineCount = 0;
  int _deadCount = 0;
  int _totalLatencyMs = 0;
  String? _currentName;
  String? _currentStatus;

  final Map<String, StreamProbeResult> _results = {};

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    try {
      final list = await widget.library.channels(widget.playlist.id);
      if (mounted) {
        setState(() {
          _channels = list;
          _total = list.length;
          _loadingChannels = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  void _start() {
    final channels = _channels;
    if (channels == null || channels.isEmpty) return;

    final cancel = CancelToken();
    _cancelToken = cancel;

    setState(() {
      _running = true;
      _done = false;
      _completed = 0;
      _liveCount = 0;
      _offlineCount = 0;
      _deadCount = 0;
      _totalLatencyMs = 0;
      _results.clear();
      _currentName = null;
      _currentStatus = null;
    });

    final stream = StreamProbe.probeChannels(
      widget.http,
      channels,
      concurrency: 6,
      timeout: const Duration(seconds: 3),
      cancel: cancel,
    );

    stream.listen(
      (progress) {
        if (!mounted) return;
        final res = progress.currentResult;
        if (res != null && progress.currentChannel != null) {
          _results[progress.currentChannel!.entry.streamUrl.trim()] = res;
          if (res.health == StreamHealth.live && res.latency != null) {
            _totalLatencyMs += res.latency!.inMilliseconds;
          }
        }
        setState(() {
          _completed = progress.completed;
          _liveCount = progress.liveCount;
          _offlineCount = progress.offlineCount;
          _deadCount = progress.deadCount;
          _currentName = progress.currentChannel?.name;
          _currentStatus = res != null
              ? (res.latency != null ? '${res.latency!.inMilliseconds}ms' : res.health.name)
              : null;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _running = false;
          _done = true;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _done = true;
        });
      },
      cancelOnError: false,
    );
  }

  Future<void> _applySort() async {
    final channels = _channels;
    if (channels == null || channels.isEmpty) return;

    final sorted = StreamProbe.sortChannelsByHealth(channels, _results);
    try {
      await widget.library.savePlaylist(widget.playlist, sorted, expected: widget.playlist);
      AppNavigator.toast(i18n('iptv_speed_test_sorted_toast'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      AppNavigator.toast(i18n('iptv_save_failed'));
    }
  }

  Future<void> _filterDead() async {
    final channels = _channels;
    if (channels == null || channels.isEmpty) return;

    final filtered = StreamProbe.filterDeadChannels(channels, _results);
    final count = channels.length - filtered.length;
    if (count <= 0) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      await widget.library.savePlaylist(widget.playlist, filtered, expected: widget.playlist);
      AppNavigator.toast(i18n('iptv_speed_test_filtered_toast', args: {'count': '$count'}));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      AppNavigator.toast(i18n('iptv_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;

    final int avgLatency = _liveCount > 0 ? (_totalLatencyMs / _liveCount).round() : 0;

    return AppDialog(
      title: i18n('iptv_speed_test_title'),
      icon: AppIcons.settingsHardwareDecoding,
      message: widget.playlist.name,
      wide: true,
      autofocus: false,
      content: _loadingChannels
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          : (_total == 0
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(i18n('iptv_speed_test_empty'), style: styles.t13),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    if (_running) ...[
                      LinearProgressIndicator(
                        value: _total > 0 ? _completed / _total : 0,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            i18n('iptv_speed_testing', args: {'completed': '$_completed', 'total': '$_total'}),
                            style: styles.t13.emphasis,
                          ),
                          if (_currentStatus != null)
                            Text(_currentStatus!, style: styles.t12.copyWith(color: scheme.primary)),
                        ],
                      ),
                      if (_currentName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _currentName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.t12.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        _Badge(
                          color: LiveSemanticColors.success(scheme.brightness),
                          label: i18n('iptv_status_live'),
                          count: _liveCount,
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          color: LiveSemanticColors.warning(scheme.brightness),
                          label: i18n('iptv_status_offline'),
                          count: _offlineCount,
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          color: scheme.error,
                          label: i18n('iptv_status_dead'),
                          count: _deadCount,
                        ),
                      ],
                    ),
                    if (_done) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          i18n('iptv_speed_test_summary', args: {
                            'total': '$_total',
                            'live': '$_liveCount',
                            'offline': '$_offlineCount',
                            'dead': '$_deadCount',
                            'avg': '$avgLatency',
                          }),
                          style: styles.t13.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ],
                )),
      actions: [
        if (!_running && !_done) ...[
          const DialogCancelButton(),
          DialogActionButton(
            key: const ValueKey('iptv-speed-test-start-btn'),
            label: i18n('iptv_speed_test_start'),
            onPressed: _total > 0 ? _start : null,
          ),
        ] else if (_running) ...[
          DialogActionButton(
            key: const ValueKey('iptv-speed-test-cancel-btn'),
            label: i18n('cancel'),
            onPressed: () {
              _cancelToken?.cancel();
              setState(() {
                _running = false;
                _done = true;
              });
            },
          ),
        ] else if (_done) ...[
          if (_deadCount > 0)
            DialogActionButton(
              key: const ValueKey('iptv-speed-test-filter-btn'),
              label: i18n('iptv_speed_test_filter_dead'),
              onPressed: _filterDead,
            ),
          DialogActionButton(
            key: const ValueKey('iptv-speed-test-sort-btn'),
            label: i18n('iptv_speed_test_apply_sort'),
            onPressed: _liveCount > 0 ? _applySort : null,
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: styles.t16.emphasis.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: styles.t11.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
