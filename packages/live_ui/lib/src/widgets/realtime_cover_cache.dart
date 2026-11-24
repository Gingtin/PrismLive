import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// In-memory and reactive cache for real-time video snapshots of live rooms.
///
/// When a room is watched, the player captures high-fidelity video frames and stores
/// them here indexed by identityKey. Room cards and previews can subscribe
/// to updates and display live snapshots rather than static profile posters.
abstract final class RealtimeCoverCache {
  static final Map<String, Uint8List> _frames = {};
  static final Map<String, ValueNotifier<Uint8List?>> _notifiers = {};

  /// Retrieves the cached frame bytes for [identityKey], if any.
  static Uint8List? get(String? identityKey) {
    if (identityKey == null || identityKey.isEmpty) return null;
    return _frames[identityKey];
  }

  /// Returns a reactive [ValueNotifier] for [identityKey].
  static ValueNotifier<Uint8List?> notifier(String identityKey) {
    return _notifiers.putIfAbsent(
      identityKey,
      () => ValueNotifier<Uint8List?>(_frames[identityKey]),
    );
  }

  /// Stores a captured video frame for [identityKey] and notifies listeners.
  static void put(String identityKey, Uint8List bytes) {
    if (identityKey.isEmpty || bytes.isEmpty) return;
    _frames[identityKey] = bytes;
    final n = _notifiers[identityKey];
    if (n != null) {
      n.value = bytes;
    }
  }

  /// Removes the cached frame for [identityKey].
  static void remove(String identityKey) {
    _frames.remove(identityKey);
    final n = _notifiers[identityKey];
    if (n != null) {
      n.value = null;
    }
  }

  /// Clears all cached frames.
  static void clear() {
    _frames.clear();
    for (final n in _notifiers.values) {
      n.value = null;
    }
  }
}

/// A widget that displays the real-time captured video frame if available in
/// [RealtimeCoverCache], falling back to [fallback].
class RealtimeCoverView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.identityKey,
    required this.fallback,
    this.showIndicator = true,
    super.key,
  });

  /// The room identity key.
  final String? identityKey;

  /// Fallback widget when no realtime capture is in cache.
  final Widget fallback;

  /// Whether to show a subtle "实时画面" indicator when displaying a captured frame.
  final bool showIndicator;

  @override
  Widget build(BuildContext context) {
    final key = identityKey;
    if (key == null || key.isEmpty) return fallback;

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: RealtimeCoverCache.notifier(key),
      builder: (context, bytes, _) {
        if (bytes == null || bytes.isEmpty) {
          return fallback;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            if (showIndicator)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '实时',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
