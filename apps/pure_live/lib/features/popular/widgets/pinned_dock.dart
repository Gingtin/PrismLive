import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/privacy/nsfw_privacy_manager.dart';

/// Top Pinned Dock (常用置顶槽) displaying 5–8 favorite platforms with active indicator,
/// proxy badges, and a direct entrance to the full SourcePickerSheet.
class PinnedDock extends StatelessWidget {
  /// Creates a [PinnedDock].
  const new({
    required this.pinnedIds,
    required this.selectedId,
    required this.onSelect,
    required this.onOpenPicker,
    this.onUnpin,
    super.key,
  });

  /// The list of pinned platform IDs (typically 5 to 8).
  final List<String> pinnedIds;

  /// Currently selected platform ID.
  final String selectedId;

  /// Callback when a platform is clicked.
  final ValueChanged<String> onSelect;

  /// Callback when the "All Sources / Drawer" button is tapped.
  final VoidCallback onOpenPicker;

  /// Callback to unpin a platform.
  final ValueChanged<String>? onUnpin;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NsfwPrivacyManager.instance,
      builder: (context, _) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final effectivePinnedIds = ((selectedId.isNotEmpty && !pinnedIds.contains(selectedId))
            ? [selectedId, ...pinnedIds]
            : pinnedIds)
        .where((id) {
          final desc = SiteIds.descriptorOf(id);
          if (desc.isNsfw && !NsfwPrivacyManager.instance.isUnlocked) return false;
          return desc.supportStatus.isPlayable;
        })
        .toList();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          // Horizontally scrollable list of pinned platform pills
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: effectivePinnedIds.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final id = effectivePinnedIds[index];
                final desc = SiteIds.descriptorOf(id);
                final isSelected = id == selectedId;

                final proxyBadgeMode = switch (desc.networkMode) {
                  NetworkMode.direct => ProxyBadgeMode.direct,
                  NetworkMode.proxyRecommended => ProxyBadgeMode.proxyRecommended,
                  NetworkMode.proxyRequired => ProxyBadgeMode.proxyRequired,
                };

                return InkWell(
                  onTap: () => onSelect(id),
                  onLongPress: onUnpin == null ? null : () => onUnpin!(id),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primary.withValues(alpha: 0.15)
                          : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? scheme.primary
                            : scheme.outlineVariant.withValues(alpha: 0.4),
                        width: isSelected ? 1.5 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlatformLogo(id, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          desc.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        if (proxyBadgeMode != ProxyBadgeMode.direct) ...[
                          const SizedBox(width: 4),
                          ProxyBadge(mode: proxyBadgeMode, compact: true),
                        ],
                        if (desc.isNsfw) ...[
                          const SizedBox(width: 4),
                          const NsfwBadge(compact: true),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 6),
          // Vertical divider
          Container(
            height: 20,
            width: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 4),

          // All Sources Drawer Button
          Tooltip(
            message: '全量平台抽屉与源分类',
            child: InkWell(
              onTap: onOpenPicker,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Remix.apps_2_line, size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '全量源',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
