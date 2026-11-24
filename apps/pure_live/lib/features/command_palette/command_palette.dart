import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/features/privacy/nsfw_privacy_manager.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// Item in the command palette.
class CommandItem {
  /// Creates a [CommandItem].
  const new({
    required this.id,
    required this.title,
    required this.category,
    required this.onExecute,
    this.subtitle,
    this.icon,
    this.platformId,
    this.proxyMode = ProxyBadgeMode.direct,
    this.shortcut,
    this.isNsfw = false,
  });

  /// Unique item identifier.
  final String id;

  /// Display title.
  final String title;

  /// Optional subtitle.
  final String? subtitle;

  /// Category name.
  final String category;

  /// Optional icon.
  final IconData? icon;

  /// Optional platform identifier.
  final String? platformId;

  /// Proxy mode for badge display.
  final ProxyBadgeMode proxyMode;

  /// Keyboard shortcut hint.
  final String? shortcut;

  /// Execution callback.
  final VoidCallback onExecute;

  /// Whether this item represents adult / NSFW content.
  final bool isNsfw;
}

/// Desktop Command Palette (`Cmd/Ctrl + K`) for instant source jump,
/// direct link navigation, and system actions.
class CommandPalette extends ConsumerStatefulWidget {
  /// Creates a [CommandPalette].
  const new({super.key});

  /// Shows the command palette in a dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const CommandPalette(),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();

  String _query = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      setState(() {
        _query = _ctrl.text.trim();
        _selectedIndex = 0;
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<CommandItem> _buildItems() {
    final items = <CommandItem>[];

    // 1. Direct input/link item if query matches URL or digits
    if (_query.isNotEmpty) {
      if (_query.startsWith('http://') || _query.startsWith('https://')) {
        items.add(
          CommandItem(
            id: 'open_url',
            title: '解析并播放直播链接',
            subtitle: _query,
            category: '快捷打开',
            icon: Icons.link_rounded,
            onExecute: () {
              Navigator.of(context).pop();
              unawaited(AppNavigator.toNamed<void>(RoutePath.kToolbox, arguments: _query));
            },
          ),
        );
      } else if (RegExp(r'^\d+$').hasMatch(_query)) {
        items.add(
          CommandItem(
            id: 'open_room_id',
            title: '按房间号/频道号检索',
            subtitle: '全网检索房间号: $_query',
            category: '快捷打开',
            icon: Icons.search_rounded,
            onExecute: () {
              Navigator.of(context).pop();
              unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch, arguments: _query));
            },
          ),
        );
      }
    }

    // 2. Platform jumping
    final isUnlocked = NsfwPrivacyManager.instance.isUnlocked;
    final allPlatforms = isUnlocked ? SiteIds.descriptors.keys : SiteIds.supported;
    for (final id in allPlatforms) {
      final desc = SiteIds.descriptorOf(id);
      if (desc.isNsfw && !isUnlocked) continue;
      // Filter out pending plugins or disabled platforms to avoid dead entries, unless adult source unlocked
      if (!desc.supportStatus.isPlayable && !desc.isNsfw) continue;

      if (_query.isEmpty || desc.matchesQuery(_query)) {
        final mode = switch (desc.networkMode) {
          NetworkMode.direct => ProxyBadgeMode.direct,
          NetworkMode.proxyRecommended => ProxyBadgeMode.proxyRecommended,
          NetworkMode.proxyRequired => ProxyBadgeMode.proxyRequired,
        };

        final catLabel = desc.categories.map((c) => c.label).join('/');
        items.add(
          CommandItem(
            id: 'platform_$id',
            title: desc.name,
            subtitle: '${desc.region.label} · $catLabel',
            category: '直播平台与源',
            platformId: id,
            proxyMode: mode,
            isNsfw: desc.isNsfw,
            onExecute: () {
              Navigator.of(context).pop();
              AppNavigator.router.go(RoutePath.kInitial);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                HomeSignals.select.value = (HomeMenu.popular, (HomeSignals.select.value?.$2 ?? 0) + 1);
                ref.read(popularCatalogProvider).currentPlatform = id;
              });
            },
          ),
        );
      }
    }

    // 3. System and setting actions
    final actions = <(String, String, String, IconData, VoidCallback, String?)>[
      (
        'iptv_manage',
        'IPTV 源管理与导入',
        '导入外部 M3U/M3U8 播放列表与频道测速',
        Icons.tv_rounded,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kIptv)),
        'I',
      ),
      (
        'multiview',
        '多路同屏监播 (Multi-View)',
        '开启 2×2 / 3×3 多路同屏同时播放与矩阵监听',
        Icons.grid_view_rounded,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kMultiview)),
        'M',
      ),
      (
        'search',
        '全平台聚合搜索',
        '跨平台主播、房间与分类搜索',
        Icons.search_rounded,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch)),
        '⌘F',
      ),
      (
        'toolbox',
        '工具箱 / 剪贴板快速解析',
        '粘贴任意平台分享链接一键解析',
        Icons.build_circle_outlined,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kToolbox)),
        '⌘L',
      ),
      (
        'history',
        '观看历史记录',
        '最近看过的房间与电台回放',
        Icons.history_rounded,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kHistory)),
        '⌘Y',
      ),
      (
        'favorites',
        '我的关注列表',
        '查看当前正在开播的关注主播',
        Icons.favorite_rounded,
        () {
          AppNavigator.router.go(RoutePath.kInitial);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            HomeSignals.select.value = (HomeMenu.favorites, (HomeSignals.select.value?.$2 ?? 0) + 1);
          });
        },
        '⌘1',
      ),
      (
        'settings',
        '应用设置与偏好',
        '外观、网络代理、硬件解码与弹幕过滤',
        Icons.settings_rounded,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings)),
        '⌘,',
      ),
      (
        'backup',
        '数据备份与恢复',
        '关注列表、历史记录及配置本地/WebDAV 同步',
        Icons.cloud_sync_rounded,
        () => unawaited(AppNavigator.toNamed<void>(RoutePath.kBackup)),
        null,
      ),
    ];

    for (final act in actions) {
      final (id, title, subtitle, icon, cb, sc) = act;
      if (_query.isEmpty ||
          title.toLowerCase().contains(_query.toLowerCase()) ||
          subtitle.toLowerCase().contains(_query.toLowerCase())) {
        items.add(
          CommandItem(
            id: id,
            title: title,
            subtitle: subtitle,
            category: '系统功能与设置',
            icon: icon,
            shortcut: sc,
            onExecute: () {
              Navigator.of(context).pop();
              cb();
            },
          ),
        );
      }
    }

    return items;
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final items = _buildItems();
    if (items.isEmpty) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, items.length - 1);
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, items.length - 1);
      });
      _scrollToSelected();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < items.length) {
        items[_selectedIndex].onExecute();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  void _scrollToSelected() {
    if (!_scrollCtrl.hasClients) return;
    const itemHeight = 56.0;
    final targetOffset = _selectedIndex * itemHeight;
    _scrollCtrl.animateTo(
      targetOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = _buildItems();

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
          child: Material(
            elevation: 16,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            color: scheme.surface,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Search Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 22, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '搜索直播源、频道号、链接或指令 (↑↓ 选择，Enter 执行)...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _ctrl.clear,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'ESC',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Results list
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 40,
                                color: scheme.outlineVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '未找到相关直播源或指令',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: item.onExecute,
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                color: isSelected
                                    ? scheme.primary.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    if (item.platformId != null)
                                      PlatformLogo(item.platformId!, size: 26)
                                    else if (item.icon != null)
                                      Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? scheme.primary.withValues(alpha: 0.2)
                                              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          item.icon,
                                          size: 16,
                                          color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                item.title,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                  color: isSelected ? scheme.primary : scheme.onSurface,
                                                ),
                                              ),
                                              if (item.proxyMode != ProxyBadgeMode.direct) ...[
                                                const SizedBox(width: 6),
                                                ProxyBadge(mode: item.proxyMode, compact: true),
                                              ],
                                              if (item.isNsfw) ...[
                                                const SizedBox(width: 6),
                                                const NsfwBadge(compact: true),
                                              ],
                                            ],
                                          ),
                                          if (item.subtitle != null)
                                            Text(
                                              item.subtitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (item.shortcut != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.shortcut!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      )
                                    else
                                      Text(
                                        item.category,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.outline,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Bottom shortcut hints
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '按 Enter 执行 · ↑↓ 移动 · Esc 退出 · 快速搜索 55+ 平台与频道',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'PrismLive Palette',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
