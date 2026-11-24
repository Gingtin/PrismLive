import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pure_live/app/commands.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/features/privacy/nsfw_privacy_manager.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// Boss Key handler: instantly mutes audio, stops playback, locks privacy,
/// navigates to home, and minimizes the window on desktop.
abstract final class BossKey {
  /// Triggers the Boss Key emergency action.
  static Future<void> trigger({BuildContext? context}) async {
    // 1. Instantly pause/mute active live room playback
    try {
      final room = RoomCommands.current.value;
      if (room != null) {
        await room.togglePlay();
      }
    } on Object catch (_) {}

    // 2. Lock NSFW privacy and wipe volatile credentials
    NsfwPrivacyManager.instance.lock();

    // 3. Return to clean initial home route
    try {
      AppNavigator.router.go(RoutePath.kInitial);
    } on Object catch (_) {}

    // 4. Minimize desktop window to taskbar/tray if running on desktop
    if (DesktopShell.supported) {
      try {
        await DesktopWindow.minimize();
      } on Object catch (_) {}
    }

    // 5. Provide discreet feedback if context is mounted
    final ctx = context ?? AppNavigator.navigatorContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
        const SnackBar(
          content: Text('已触发老板键：已静音并切换至主页'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}
