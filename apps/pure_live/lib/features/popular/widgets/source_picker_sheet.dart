import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';

/// Modal bottom sheet or side panel for selecting among 55+ platforms and IPTV
/// sources with multi-dimensional filtering, proxy badges, and instant search.
class SourcePickerSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const new({
    required this.selectedPlatform,
    required this.onSelect,
    this.pinnedIds = const [],
    this.onTogglePin,
    super.key,
  });

  /// Currently active platform.
  final String selectedPlatform;

  /// Callback when a platform is selected.
  final ValueChanged<String> onSelect;

  /// IDs currently pinned in the dock.
  final List<String> pinnedIds;

  /// Callback to toggle pinning a platform to the dock.
  final ValueChanged<String>? onTogglePin;

  /// Shows the source picker as an adaptive bottom sheet or modal side panel.
  static Future<void> show({
    required BuildContext context,
    required String selectedPlatform,
    required ValueChanged<String> onSelect,
    List<String> pinnedIds = const [],
    ValueChanged<String>? onTogglePin,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 720;

    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: SourcePickerSheet(
                selectedPlatform: selectedPlatform,
                onSelect: (id) {
                  Navigator.of(ctx).pop();
                  onSelect(id);
                },
                pinnedIds: pinnedIds,
                onTogglePin: onTogglePin,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
        ),
        child: Material(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SourcePickerSheet(
            selectedPlatform: selectedPlatform,
            onSelect: (id) {
              Navigator.of(ctx).pop();
              onSelect(id);
            },
            pinnedIds: pinnedIds,
            onTogglePin: onTogglePin,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<SourcePickerSheet> createState() => _SourcePickerSheetState();
}

class _SourcePickerSheetState extends ConsumerState<SourcePickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  SourceRegion? _filterRegion;
  NetworkMode? _filterNetwork;
  SourceCategory? _filterCategory;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const allIds = SiteIds.supported;

    // Filter available platforms
    final allMatching = allIds.map(SiteIds.descriptorOf).where((desc) {
      if (desc.isNsfw) return false; // Hard Invariant #5: strictly hidden by default

      if (_searchQuery.isNotEmpty && !desc.matchesQuery(_searchQuery)) {
        return false;
      }
      if (_filterRegion != null && desc.region != _filterRegion) {
        return false;
      }
      if (_filterNetwork != null && desc.networkMode != _filterNetwork) {
        return false;
      }
      if (_filterCategory != null && !desc.categories.contains(_filterCategory)) {
        return false;
      }
      return true;
    }).toList();

    final playable = allMatching.where((d) => d.supportStatus.isPlayable).toList();
    final pending = allMatching.where((d) => d.supportStatus == SourceSupportStatus.pluginPending).toList();

    return Column(
      children: [
        // Header and Drag handle
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Remix.apps_2_line, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '全部直播平台与源目录',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Remix.close_line, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Search field with instant Pinyin & Name filtering
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索平台 (支持中英文及拼音首字母，如 bz, dy, tw)...',
                  prefixIcon: const Icon(Remix.search_2_line, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Remix.close_circle_fill, size: 16),
                          onPressed: _searchCtrl.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Domain & Region Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            spacing: 6,
            children: [
              FilterChip(
                label: const Text('全部'),
                selected: _filterRegion == null && _filterNetwork == null,
                onSelected: (_) => setState(() {
                  _filterRegion = null;
                  _filterNetwork = null;
                  _filterCategory = null;
                }),
              ),
              FilterChip(
                label: const Text('国内主流'),
                selected: _filterRegion == SourceRegion.domestic,
                onSelected: (sel) => setState(() => _filterRegion = sel ? SourceRegion.domestic : null),
              ),
              FilterChip(
                label: const Text('国际热门'),
                selected: _filterRegion == SourceRegion.international,
                onSelected: (sel) => setState(() => _filterRegion = sel ? SourceRegion.international : null),
              ),
              FilterChip(
                label: const Text('日韩东南亚'),
                selected: _filterRegion == SourceRegion.eastAsia || _filterRegion == SourceRegion.southeastAsia,
                onSelected: (sel) => setState(() => _filterRegion = sel ? SourceRegion.eastAsia : null),
              ),
              FilterChip(
                label: const Text('仅看直连'),
                selected: _filterNetwork == NetworkMode.direct,
                onSelected: (sel) => setState(() => _filterNetwork = sel ? NetworkMode.direct : null),
              ),
              FilterChip(
                label: const Text('需代理'),
                selected: _filterNetwork == NetworkMode.proxyRequired,
                onSelected: (sel) => setState(() => _filterNetwork = sel ? NetworkMode.proxyRequired : null),
              ),
            ],
          ),
        ),

        const Divider(height: 12),

        // Grid of Platforms
        Expanded(
          child: playable.isEmpty && pending.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Remix.search_eye_line, size: 40, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text('未找到匹配的直播平台或源', style: TextStyle(color: theme.colorScheme.outline)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (playable.isNotEmpty)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisExtent: 68,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: playable.length,
                        itemBuilder: (context, index) {
                          final desc = playable[index];
                          final isSelected = desc.id == widget.selectedPlatform;
                          final isPinned = widget.pinnedIds.contains(desc.id);

                          return InkWell(
                            onTap: () => widget.onSelect(desc.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                                    : theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  PlatformLogo(desc.id),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          desc.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            fontSize: 13,
                                            color: isSelected ? theme.colorScheme.primary : null,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            ProxyBadge(
                                              mode: switch (desc.networkMode) {
                                                NetworkMode.direct => ProxyBadgeMode.direct,
                                                NetworkMode.proxyRecommended => ProxyBadgeMode.proxyRecommended,
                                                NetworkMode.proxyRequired => ProxyBadgeMode.proxyRequired,
                                              },
                                              compact: true,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.onTogglePin != null)
                                    IconButton(
                                      icon: Icon(
                                        isPinned ? Remix.pushpin_fill : Remix.pushpin_line,
                                        size: 16,
                                        color: isPinned ? theme.colorScheme.primary : theme.colorScheme.outline,
                                      ),
                                      tooltip: isPinned ? '取消置顶' : '置顶到首屏',
                                      onPressed: () => widget.onTogglePin!(desc.id),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: Icon(Remix.puzzle_line, size: 20, color: theme.colorScheme.primary),
                          title: Text(
                            '待接入扩展平台 (${pending.length})',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            '等待 Phase 2 QuickJS-NG 沙箱热更接入',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          children: [
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisExtent: 68,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: pending.length,
                              itemBuilder: (context, index) {
                                final desc = pending[index];
                                return InkWell(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('${desc.name} 平台插件接入中，将在 Phase 2 沙箱热更上线'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Opacity(opacity: 0.6, child: PlatformLogo(desc.id)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                desc.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '待接入',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: theme.colorScheme.outline,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
