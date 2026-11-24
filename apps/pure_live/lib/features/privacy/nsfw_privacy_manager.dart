import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';

/// Quadruple Privacy Isolation Manager for Adult/NSFW content (Hard Invariant #5).
///
/// Four-fold Privacy Shield:
/// 1. Entry invisibility: 100% invisible by default across catalog, search, recommendations, IPTV.
/// 2. Code isolation: separate descriptors, strict runtime gating.
/// 3. Zero-trace memory storage: volatile sandboxed cookies/tokens and in-memory LRU thumbnail cache,
///    erased on lock, boss key, or process exit. Never written to disk or photo gallery.
/// 4. System shield & Boss Key: Android WindowManager.LayoutParams.FLAG_SECURE bridge,
///    instant mute, pause, minimize, and navigation to clean home.
class NsfwPrivacyManager extends ChangeNotifier {
  new _();

  /// Singleton instance.
  static final NsfwPrivacyManager instance = NsfwPrivacyManager._();

  static const MethodChannel _shieldChannel =
      MethodChannel('com.mystyle.purelive/privacy_shield');

  bool _isUnlocked = false;

  /// Whether NSFW sources and features are currently unlocked.
  /// Strictly defaults to false (locked/invisible).
  bool get isUnlocked => _isUnlocked;

  /// Unlocks NSFW mode for test environments without opening UI dialogs.
  @visibleForTesting
  void unlockForTesting() {
    _isUnlocked = true;
    notifyListeners();
  }

  /// Hashed 6-digit PIN (SHA-256 with salt) for security lock.
  String? _hashedPin;
  String? _pinSalt;

  /// Whether a custom PIN lock is currently configured.
  bool get hasPin => _hashedPin != null && _pinSalt != null;

  /// Volatile sandboxed cookies/tokens for adult platforms (erased on lock/exit).
  final Map<String, String> _sandboxedSessionTokens = {};

  /// In-memory volatile thumbnail cache for adult content (erased on lock/exit).
  final Map<String, Uint8List> _volatileThumbnailCache = {};

  /// Sets or updates the 6-digit access PIN.
  void setPin(String pin) {
    if (pin.length != 6 || int.tryParse(pin) == null) {
      throw ArgumentError.value(pin, 'pin', 'PIN must be exactly 6 digits');
    }
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64Url.encode(saltBytes);
    final hash = sha256.convert(utf8.encode('$salt:$pin')).toString();

    _pinSalt = salt;
    _hashedPin = hash;
    notifyListeners();
  }

  /// Verifies a candidate PIN against the stored hash.
  bool verifyPin(String pin) {
    if (_hashedPin == null || _pinSalt == null) return false;
    final candidateHash = sha256.convert(utf8.encode('$_pinSalt:$pin')).toString();
    return candidateHash == _hashedPin;
  }

  /// Clears the configured PIN lock.
  void clearPin() {
    _hashedPin = null;
    _pinSalt = null;
    notifyListeners();
  }

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

  /// Stores an in-memory thumbnail snapshot (strictly never persisted to disk).
  void storeVolatileThumbnail(String key, Uint8List bytes) {
    if (!_isUnlocked) return;
    if (_volatileThumbnailCache.length >= 50) {
      _volatileThumbnailCache.remove(_volatileThumbnailCache.keys.first);
    }
    _volatileThumbnailCache[key] = bytes;
  }

  /// Retrieves an in-memory thumbnail snapshot, or null if locked.
  Uint8List? getVolatileThumbnail(String key) {
    if (!_isUnlocked) return null;
    return _volatileThumbnailCache[key];
  }

  /// Updates the native window security flag (Android FLAG_SECURE) to prevent screenshots
  /// and hide window contents in task switcher.
  Future<void> _updateWindowSecurity(bool secure) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _shieldChannel.invokeMethod<void>('setSecure', {'enabled': secure});
      }
    } on Object catch (_) {}
  }

  /// Locks NSFW mode immediately: wipes sandboxed tokens, clears thumbnail cache,
  /// disables FLAG_SECURE shield, and notifies listeners.
  void lock() {
    if (!_isUnlocked) return;
    _isUnlocked = false;
    _sandboxedSessionTokens.clear();
    _volatileThumbnailCache.clear();
    unawaited(_updateWindowSecurity(false));
    notifyListeners();
  }

  /// Filters a list of [SourceDescriptor]s, strictly removing any NSFW sources
  /// unless currently unlocked.
  List<SourceDescriptor> filterDescriptors(Iterable<SourceDescriptor> descriptors) {
    if (_isUnlocked) return descriptors.toList();
    return descriptors.where((d) => !d.isNsfw).toList();
  }

  /// Prompts the user with a PIN verification dialog or age confirmation dialog.
  Future<bool> requestUnlock(BuildContext context) async {
    if (_isUnlocked) return true;

    if (hasPin) {
      final verified = await _promptPinDialog(context);
      if (verified == true) {
        _isUnlocked = true;
        unawaited(_updateWindowSecurity(true));
        notifyListeners();
        return true;
      }
      return false;
    }

    final confirmed = await _promptAgeConfirmationDialog(context);
    if (confirmed == true) {
      _isUnlocked = true;
      unawaited(_updateWindowSecurity(true));
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool?> _promptPinDialog(BuildContext context) {
    final pinController = TextEditingController();
    String? errorMessage;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          return AlertDialog(
            icon: Icon(Icons.lock_outline, size: 36, color: theme.colorScheme.primary),
            title: const Text('敏感内容访问密码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '请输入 6 位数字隐私密码解锁成人与敏感源。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '6 位数字密码',
                    errorText: errorMessage,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                  onSubmitted: (val) {
                    if (verifyPin(val.trim())) {
                      Navigator.of(ctx).pop(true);
                    } else {
                      setState(() => errorMessage = '密码错误，请重试');
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final pin = pinController.text.trim();
                  if (verifyPin(pin)) {
                    Navigator.of(ctx).pop(true);
                  } else {
                    setState(() => errorMessage = '密码错误，请重试');
                  }
                },
                child: const Text('解锁'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool?> _promptAgeConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
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
                      '开启系统防截屏护盾（FLAG_SECURE），退后台自动防窥。',
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
                      '随时可按 Ctrl/Cmd+Shift+H 触发老板键瞬时隐藏并静音。',
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
  }
}
