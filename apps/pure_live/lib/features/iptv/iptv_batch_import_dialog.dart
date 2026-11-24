import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Import mode for batch extracted sources.
enum IptvBatchMode {
  /// Each source becomes its own subscription playlist.
  separate,

  /// All sources are combined into one grouped playlist.
  merge,
}

/// Dialog for smart extraction and batch importing of IPTV sources.
class IptvBatchImportDialog extends ConsumerStatefulWidget {
  /// Creates the batch import dialog.
  const new({
    required this.importer,
    this.initialText = '',
    this.onConfirmReplace,
    super.key,
  });

  /// The IPTV importer.
  final IptvImporter importer;

  /// Optional pre-filled text.
  final String initialText;

  /// Optional replacement confirmation callback.
  final IptvReplaceConfirm? onConfirmReplace;

  @override
  ConsumerState<IptvBatchImportDialog> createState() => _IptvBatchImportDialogState();
}

class _IptvBatchImportDialogState extends ConsumerState<IptvBatchImportDialog> {
  late final TextEditingController _textController;
  late final TextEditingController _mergedNameController;
  List<ExtractedSource> _sources = const [];
  final Set<String> _selectedUrls = <String>{};
  IptvBatchMode _mode = IptvBatchMode.separate;
  bool _running = false;
  String? _progressMessage;
  double? _progressValue;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _mergedNameController = TextEditingController(text: i18n('iptv_batch_merged_name_default'));
    _textController.addListener(_onTextChanged);
    if (widget.initialText.isNotEmpty) {
      _parseText(widget.initialText);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_readClipboard()));
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _mergedNameController.dispose();
    super.dispose();
  }

  Future<void> _readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted || text.isEmpty) return;
      if (_textController.text.isEmpty && IptvSmartExtractor.extract(text).isNotEmpty) {
        _textController.text = text;
      }
    } on Object catch (_) {}
  }

  void _onTextChanged() {
    _parseText(_textController.text);
  }

  void _parseText(String text) {
    final list = IptvSmartExtractor.extract(text);
    setState(() {
      _sources = list;
      _selectedUrls
        ..clear()
        ..addAll(list.map((s) => s.url));
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedUrls.length == _sources.length) {
        _selectedUrls.clear();
      } else {
        _selectedUrls
          ..clear()
          ..addAll(_sources.map((s) => s.url));
      }
    });
  }

  Future<void> _startImport() async {
    final selected = _sources.where((s) => _selectedUrls.contains(s.url)).toList();
    if (selected.isEmpty || _running) return;

    setState(() {
      _running = true;
      _progressValue = 0;
      _progressMessage = i18n('iptv_import_running');
    });

    try {
      if (_mode == IptvBatchMode.separate) {
        final result = await widget.importer.importBatchSources(
          sources: selected,
          confirmReplace: widget.onConfirmReplace,
          onProgress: (current, total, name) {
            if (!mounted) return;
            setState(() {
              _progressValue = current / total;
              _progressMessage = i18n('iptv_batch_progress', args: {
                'current': '$current',
                'total': '$total',
                'name': name,
              });
            });
          },
        );
        if (result.succeeded > 0) {
          final playlists = await widget.importer.library.playlists();
          final first = playlists.where((p) => !p.isHot && selected.any((s) => s.name.toLowerCase() == p.name.toLowerCase())).firstOrNull;
          if (first != null) {
            await ref.read(storeProvider).settings.set(Settings.iptvPopularPlaylist, first.id);
          }
        }
        if (!mounted) return;
        Navigator.pop(
          context,
          IptvImportResult(
            IptvImportStatus.imported,
            issues: [
              PlaylistIssue(
                0,
                i18n('iptv_batch_success', args: {
                  'success': '${result.succeeded}',
                  'failed': '${result.failed}',
                }),
              ),
            ],
          ),
        );
      } else {
        final mergedName = _mergedNameController.text.trim().isEmpty
            ? i18n('iptv_batch_merged_name_default')
            : _mergedNameController.text.trim();

        final result = await widget.importer.importAggregatedSources(
          sources: selected,
          name: mergedName,
          confirmReplace: widget.onConfirmReplace,
          onProgress: (current, total, name) {
            if (!mounted) return;
            setState(() {
              _progressValue = current / total;
              _progressMessage = i18n('iptv_batch_merging', args: {
                'current': '$current',
                'total': '$total',
              });
            });
          },
        );
        if (result.isImported && result.id != null) {
          await ref.read(storeProvider).settings.set(Settings.iptvPopularPlaylist, result.id!);
        }
        if (!mounted) return;
        Navigator.pop(context, result);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progressMessage = 'Error: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedCount = _selectedUrls.length;

    return AppDialog(
      title: i18n('iptv_batch_title'),
      icon: AppIcons.batchSources,
      wide: true,
      autofocus: false,
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top quick tools row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    i18n('iptv_batch_input_label'),
                    style: context.textStyles.t14.emphasis,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        icon: const Icon(AppIcons.pasteText, size: 16),
                        label: Text(i18n('iptv_batch_paste_clipboard')),
                        onPressed: _running ? null : _readClipboard,
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        icon: const Icon(AppIcons.clearField, size: 16),
                        label: Text(i18n('iptv_batch_clear')),
                        onPressed: _running
                            ? null
                            : () {
                                _textController.clear();
                                _parseText('');
                              },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Multi-line input field
              TextField(
                controller: _textController,
                readOnly: _running,
                maxLines: 4,
                minLines: 2,
                style: context.textStyles.t13,
                decoration: InputDecoration(
                  hintText: i18n('iptv_batch_input_hint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              // Extracted sources summary & preview
              if (_sources.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        i18n('iptv_batch_detected_count', args: {'count': '${_sources.length}'}),
                        style: context.textStyles.t12.emphasis.copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ),
                    TextButton(
                      onPressed: _running ? null : _toggleSelectAll,
                      child: Text(
                        _selectedUrls.length == _sources.length
                            ? i18n('iptv_batch_deselect_all')
                            : i18n('iptv_batch_select_all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _sources.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    itemBuilder: (context, index) {
                      final item = _sources[index];
                      final isChecked = _selectedUrls.contains(item.url);
                      return CheckboxListTile(
                        dense: true,
                        value: isChecked,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(item.name, style: context.textStyles.t13.emphasis),
                        subtitle: Text(
                          item.url,
                          style: context.textStyles.t11.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: _running
                            ? null
                            : (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedUrls.add(item.url);
                                  } else {
                                    _selectedUrls.remove(item.url);
                                  }
                                });
                              },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),

                // Import Mode Selector
                Text(
                  i18n('iptv_batch_mode_label'),
                  style: context.textStyles.t14.emphasis,
                ),
                const SizedBox(height: 6),
                RadioGroup<IptvBatchMode>(
                  groupValue: _mode,
                  onChanged: (v) {
                    if (!_running && v != null) setState(() => _mode = v);
                  },
                  child: Column(
                    children: [
                      RadioListTile<IptvBatchMode>(
                        dense: true,
                        value: IptvBatchMode.separate,
                        title: Text(i18n('iptv_batch_mode_separate'), style: context.textStyles.t13.emphasis),
                        subtitle: Text(i18n('iptv_batch_mode_separate_desc'), style: context.textStyles.t11),
                      ),
                      RadioListTile<IptvBatchMode>(
                        dense: true,
                        value: IptvBatchMode.merge,
                        title: Text(i18n('iptv_batch_mode_merge'), style: context.textStyles.t13.emphasis),
                        subtitle: Text(i18n('iptv_batch_mode_merge_desc'), style: context.textStyles.t11),
                      ),
                    ],
                  ),
                ),

                if (_mode == IptvBatchMode.merge) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _mergedNameController,
                      style: context.textStyles.t13,
                      decoration: InputDecoration(
                        labelText: i18n('iptv_batch_merged_name'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ],

              // Progress bar
              if (_running) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progressValue,
                    minHeight: 6,
                  ),
                ),
                if (_progressMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_progressMessage!, style: context.textStyles.t12),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        DialogCancelButton(label: i18n(_running ? 'close' : 'cancel')),
        DialogActionButton(
          label: i18n('iptv_batch_start_import', args: {'count': '$selectedCount'}),
          busy: _running,
          onPressed: selectedCount == 0 || _running ? null : _startImport,
        ),
      ],
    );
  }
}
