import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Opens the 10-band audio equalizer sheet for [controller].
void showAudioEqualizerSheet(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.equalizer);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      heightFactor: 0.65,
      builder: (_, close) => AudioEqualizerSheet(controller: controller, onClose: close),
    ),
  );
}

/// The 10-band graphic audio equalizer panel with scene presets.
class AudioEqualizerSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const new({
    required this.controller,
    required this.onClose,
    this.dragToClose = false,
    super.key,
  });

  /// The room controller.
  final LiveRoomController controller;

  /// Closes the sheet.
  final VoidCallback onClose;

  /// Drag downward to close.
  final bool dragToClose;

  @override
  ConsumerState<AudioEqualizerSheet> createState() => _AudioEqualizerSheetState();
}

class _AudioEqualizerSheetState extends ConsumerState<AudioEqualizerSheet> {
  late String _currentPreset;
  late Map<String, double> _currentBands;
  late String _currentChannelMode;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(storeProvider).settings;
    _currentPreset = settings.get(Settings.audioEqualizerPreset);
    final custom = settings.get(Settings.audioEqualizerBands);
    _currentBands = Map.of(AudioEqualizerConsts.resolveBands(_currentPreset, custom));
    _currentChannelMode = settings.get(Settings.audioChannelMode);
  }

  void _onPresetSelected(String preset) {
    final settings = ref.read(storeProvider).settings;
    setState(() {
      _currentPreset = preset;
      final custom = settings.get(Settings.audioEqualizerBands);
      _currentBands = Map.of(AudioEqualizerConsts.resolveBands(preset, custom));
    });
    unawaited(settings.set(Settings.audioEqualizerPreset, preset));
    unawaited(widget.controller.session.setAudioEqualizer(_currentBands));
  }

  void _onChannelModeSelected(String mode) {
    final settings = ref.read(storeProvider).settings;
    setState(() => _currentChannelMode = mode);
    unawaited(settings.set(Settings.audioChannelMode, mode));
    unawaited(widget.controller.session.setAudioChannelMode(mode));
  }

  void _onBandChanged(String freq, double value) {
    final settings = ref.read(storeProvider).settings;
    setState(() {
      _currentPreset = 'custom';
      _currentBands[freq] = value;
    });
    unawaited(settings.set(Settings.audioEqualizerPreset, 'custom'));
    unawaited(settings.set(Settings.audioEqualizerBands, _currentBands));
    unawaited(widget.controller.session.setAudioEqualizer(_currentBands));
  }

  void _reset() {
    _onPresetSelected('off');
    _onChannelModeSelected('stereo');
  }

  @override
  Widget build(BuildContext context) {
    const presetKeys = ['off', 'vocal', 'bass_boost', 'treble_boost', 'cinema', 'custom'];

    return RoomSidePanel(
      key: const ValueKey('audio-equalizer-sheet'),
      title: i18n('audio_equalizer'),
      onClose: widget.onClose,
      dragToClose: widget.dragToClose,
      actions: [
        TextButton(
          key: const ValueKey('equalizer-reset'),
          onPressed: _reset,
          child: Text(i18n('reset')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preset chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final preset in presetKeys) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(i18n('equalizer_preset_$preset')),
                      selected: _currentPreset == preset,
                      onSelected: (selected) {
                        if (selected) _onPresetSelected(preset);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // 10 vertical sliders
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  for (var i = 0; i < AudioEqualizerConsts.frequencies.length; i++) ...[
                    _BandSliderColumn(
                      freqKey: AudioEqualizerConsts.frequencies[i],
                      freqLabel: AudioEqualizerConsts.frequencyLabels[i],
                      gain: _currentBands[AudioEqualizerConsts.frequencies[i]] ?? 0.0,
                      onChanged: (val) => _onBandChanged(AudioEqualizerConsts.frequencies[i], val),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Channel mode chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  i18n('audio_channel_mode'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                for (final mode in ['stereo', 'mono', 'left_to_both', 'right_to_both']) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(i18n('audio_channel_$mode')),
                      selected: _currentChannelMode == mode,
                      onSelected: (selected) {
                        if (selected) _onChannelModeSelected(mode);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BandSliderColumn extends StatelessWidget {
  const new({
    required this.freqKey,
    required this.freqLabel,
    required this.gain,
    required this.onChanged,
  });

  final String freqKey;
  final String freqLabel;
  final double gain;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gainText = gain > 0 ? '+${gain.toStringAsFixed(1)}' : gain.toStringAsFixed(1);

    return SizedBox(
      width: 58,
      child: Column(
        children: [
          // dB indicator
          Text(
            '${gainText}dB',
            style: theme.textTheme.labelSmall?.copyWith(
              color: gain.abs() > 0.01 ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: gain.abs() > 0.01 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          // Slider
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: gain.clamp(-12.0, 12.0),
                  min: -12,
                  max: 12,
                  divisions: 48,
                  onChanged: (v) => onChanged((v * 2).round() / 2),
                ),
              ),
            ),
          ),
          // Frequency label
          Text(
            freqLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
