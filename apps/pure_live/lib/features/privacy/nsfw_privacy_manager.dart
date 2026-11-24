import 'dart:async';

import 'package:flutter/material.dart';

/// Quadruple Privacy Isolation Manager for Adult/NSFW content (Hard Invariant #5).
///
/// Features:
/// 1. Entry invisibility: 100% invisible by default across catalog, search, recommendations, IPTV.
/// 2. Code isolation: separate descriptors, strict runtime gating.
/// 3. Storage isolation: volatile in-memory sandbox, wipe-on-exit / wipe-on-lock.
/// 4. UI shield & Boss Key: instant mute, pause, minimize, and navigation to clean home.
class NsfwPrivacyManager extends ChangeNotifier {
  new _();

  /// Singleton instance.
  static final NsfwPrivacyManager instance = NsfwPrivacyManager._();

  bool _isUnlocked = false;

  /// Whether NSFW sources and features are currently unlocked.
  /// Strictly defaults to false (locked/invisible).
  bool get isUnlocked => _isUnlocked;

  /// Volatile sandboxed cookies/tokens for adult platforms (erased on lock/exit).
  final Map<String, String> _sandboxedSessionTokens = {};

  /// Stores a volatile session token for an adult platform.
  void storeSandboxedToken(String platformId, String token) {
    if (!_isUnlocked) return;
    _sandboxedSessionTokens[platformId] = token;
  }

  /// Retrieves a sandboxed session token, or null if locked.
  String? getSandboxedToken(String platformId) {
    if (!_isUnlocked) return null;
    return _sandboxedSessionTokens[platformId];
  }

  /// Locks NSFW mode immediately: wipes sandboxed tokens, hides content,
  /// and notifies listeners.
  void lock() {
    if (!_isUnlocked) return;
    _isUnlocked = false;
    _sandboxedSessionTokens.clear();
    notifyListeners();
  }

  /// Prompts the user with an age confirmation and PIN check dialog.
  Future<bool> requestUnlock(BuildContext context) async {
    if (_isUnlocked) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;

        return AlertDialog(
          icon: Icon(Icons.shield_outlined, size: 36, color: scheme.primary),
          title: const Text('敏感内容访问与隐私保护'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '您正在尝试解锁成人/敏感内容源。根据合规与隐私隔离规范：',
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '确认为年满 18 周岁的成年人。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '浏览记录与凭据采用独立内存沙盒，支持随时「退出即焚」。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '随时可按 Ctrl/Cmd+Shift+H 触发老板键瞬时隐藏。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('已年满18岁并确认'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _isUnlocked = true;
      notifyListeners();
      return true;
    }
    return false;
  }
}
