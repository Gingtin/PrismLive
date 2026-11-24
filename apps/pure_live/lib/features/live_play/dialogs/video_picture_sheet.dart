import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

/// Opens the picture color tuning sheet for [controller].
void showVideoPictureSheet(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.pictureColor);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      heightFactor: 0.58,
      builder: (_, close) => VideoPictureSheet(controller: controller, onClose: close),
    ),
  );
}

/// The picture color tuning panel (brightness, contrast, saturation, gamma).
class VideoPictureSheet extends ConsumerStatefulWidget {
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
  ConsumerState<VideoPictureSheet> createState() => _VideoPictureSheetState();
}

class _VideoPictureSheetState extends ConsumerState<VideoPictureSheet> {
  late int _brightness;
  late int _contrast;
  late int _saturation;
  late int _gamma;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(storeProvider).settings;
    _brightness = settings.get(Settings.videoBrightness);
    _contrast = settings.get(Settings.videoContrast);
    _saturation = settings.get(Settings.videoSaturation);
    _gamma = settings.get(Settings.videoGamma);
  }

  void _applyAndSave() {
    final settings = ref.read(storeProvider).settings;
    unawaited(settings.set(Settings.videoBrightness, _brightness));
    unawaited(settings.set(Settings.videoContrast, _contrast));
    unawaited(settings.set(Settings.videoSaturation, _saturation));
    unawaited(settings.set(Settings.videoGamma, _gamma));
    unawaited(widget.controller.session.setPictureColor(
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      gamma: _gamma,
    ));
  }

  void _reset() {
    setState(() {
      _brightness = 0;
      _contrast = 0;
      _saturation = 0;
      _gamma = 0;
    });
    _applyAndSave();
  }

  @override
  Widget build(BuildContext context) {
    return RoomSidePanel(
      key: const ValueKey('video-picture-sheet'),
      title: i18n('video_picture_color'),
      onClose: widget.onClose,
      dragToClose: widget.dragToClose,
      actions: [
        TextButton(
          key: const ValueKey('picture-color-reset'),
          onPressed: _reset,
          child: Text(i18n('reset')),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          PanelCard(
            children: [
              SettingSliderRow(
                settingKey: 'video_brightness',
                title: i18n('video_brightness'),
                value: _brightness.toDouble(),
                min: -50,
                max: 50,
                divisions: 100,
                display: _brightness > 0 ? '+$_brightness' : '$_brightness',
                onChanged: (val) {
                  setState(() => _brightness = val.round());
                  _applyAndSave();
                },
              ),
              SettingSliderRow(
                settingKey: 'video_contrast',
                title: i18n('video_contrast'),
                value: _contrast.toDouble(),
                min: -50,
                max: 50,
                divisions: 100,
                display: _contrast > 0 ? '+$_contrast' : '$_contrast',
                onChanged: (val) {
                  setState(() => _contrast = val.round());
                  _applyAndSave();
                },
              ),
              SettingSliderRow(
                settingKey: 'video_saturation',
                title: i18n('video_saturation'),
                value: _saturation.toDouble(),
                min: -50,
                max: 50,
                divisions: 100,
                display: _saturation > 0 ? '+$_saturation' : '$_saturation',
                onChanged: (val) {
                  setState(() => _saturation = val.round());
                  _applyAndSave();
                },
              ),
              SettingSliderRow(
                settingKey: 'video_gamma',
                title: i18n('video_gamma'),
                value: _gamma.toDouble(),
                min: -50,
                max: 50,
                divisions: 100,
                display: _gamma > 0 ? '+$_gamma' : '$_gamma',
                onChanged: (val) {
                  setState(() => _gamma = val.round());
                  _applyAndSave();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
