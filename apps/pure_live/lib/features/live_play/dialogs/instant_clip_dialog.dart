import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/record/record_state.dart';

/// Shows the instant clip dialog to capture a 30s or 60s highlight clip.
Future<void> showInstantClipDialog(BuildContext context, LiveRoomController controller) async {
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => _InstantClipDialog(controller: controller),
  );
}

class _InstantClipDialog extends ConsumerStatefulWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  ConsumerState<_InstantClipDialog> createState() => _InstantClipDialogState();
}

class _InstantClipDialogState extends ConsumerState<_InstantClipDialog> {
  bool _clipping = false;

  Future<void> _startClip(int seconds) async {
    final recording = ref.read(recordingProvider);
    if (recording == null || !recording.available) {
      AppNavigator.toast(i18n('archive_record_unavailable'));
      return;
    }
    if (!await recording.ensureStorageAccess()) return;

    final room = widget.controller.room;
    final recorder = recording.recorder;
    if (recorder == null) return;

    var task = recording.taskFor(room);
    if (task != null && recordBusy(task)) {
      AppNavigator.toast(i18n('record_already_active'));
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _clipping = true);
    if (!mounted) return;
    Navigator.pop(context);

    AppNavigator.toast(i18n('instant_clip_started', args: {'seconds': '$seconds'}));

    task = await recording.addTask(room);
    if (task == null) {
      AppNavigator.toast(i18n('record_panel_start_failed'));
      return;
    }

    // Schedule stop after designated seconds
    Timer(Duration(seconds: seconds), () async {
      try {
        final currentTask = recording.taskFor(room);
        if (currentTask != null && recordBusy(currentTask)) {
          await recorder.stopTask(currentTask);
          AppNavigator.toast(i18n('instant_clip_saved', args: {'seconds': '$seconds'}));
        }
      } on Object catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: i18n('instant_clip_title'),
      message: i18n('instant_clip_subtitle'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(i18n('cancel')),
        ),
        FilledButton.tonal(
          key: const ValueKey('clip-30s'),
          onPressed: _clipping ? null : () => _startClip(30),
          child: Text(i18n('instant_clip_30s')),
        ),
        FilledButton(
          key: const ValueKey('clip-60s'),
          onPressed: _clipping ? null : () => _startClip(60),
          child: Text(i18n('instant_clip_60s')),
        ),
      ],
    );
  }
}
