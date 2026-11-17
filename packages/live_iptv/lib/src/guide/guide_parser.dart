import 'dart:convert';

import 'package:live_iptv/src/model.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

/// What a programme guide parser read.
@immutable
final class ParsedGuide {
  /// Creates a result.
  new({required List<GuideChannel> channels, required List<EpgProgramme> programmes})
    : channels = List.unmodifiable(channels),
      programmes = List.unmodifiable(programmes);

  /// Channels in file order.
  final List<GuideChannel> channels;

  /// Programmes in file order, without a source id.
  final List<EpgProgramme> programmes;

  /// Whether nothing was read (3.x rejected such a file as unsupported).
  bool get isEmpty => channels.isEmpty && programmes.isEmpty;
}

/// The guide formats.
enum GuideFormat {
  /// XMLTV (`.xml`, `.xml.gz`).
  xmltv,

  /// The JSON guide 3.x read.
  json;

  /// The format of decoded [text]: a JSON object or array is [json],
  /// everything else XMLTV (3.x chose by file extension, `.json` or not).
  static GuideFormat detect(String text) {
    final start = text.trimLeft();
    return start.startsWith('{') || start.startsWith('[') ? json : xmltv;
  }
}

/// Parses decoded guide [text] in [format] (detected when null). Malformed
/// XML or JSON throws [FormatException], so a broken download never replaces
/// a saved guide.
ParsedGuide parseGuide(String text, {GuideFormat? format}) => switch (format ?? GuideFormat.detect(text)) {
  GuideFormat.xmltv => XmltvParser.parse(text),
  GuideFormat.json => JsonGuideParser.parse(text),
};

/// Parses XMLTV with a pull parser (3.x built a DOM of the whole guide).
///
/// Reads `<channel id>` with its `<display-name>`s and first `<icon src>`,
/// and `<programme channel start stop catchup-id>` with the first `<title>`,
/// `<sub-title>`, `<desc>`, `<category>` and `<episode-num>`. Programmes
/// without channel, start, stop or title, or with a bad time, are skipped.
abstract final class XmltvParser {
  static const Set<String> _programmeFields = {'title', 'sub-title', 'desc', 'category', 'episode-num'};

  /// Parses [text].
  static ParsedGuide parse(String text) {
    final channels = <GuideChannel>[];
    final programmes = <EpgProgramme>[];
    _Channel? channel;
    _Programme? programme;
    String? field;
    final buffer = StringBuffer();
    try {
      for (final event in parseEvents(text, validateNesting: true, validateDocument: true)) {
        switch (event) {
          case final XmlStartElementEvent start:
            final name = start.localName;
            if (name == 'channel' && channel == null && programme == null) {
              final id = _attribute(start, 'id');
              if (start.isSelfClosing) {
                if (id != null) channels.add(GuideChannel(id: id));
              } else {
                channel = _Channel(id);
              }
            } else if (name == 'programme' && channel == null && programme == null) {
              if (!start.isSelfClosing) {
                programme = _Programme(
                  channel: _attribute(start, 'channel'),
                  start: _attribute(start, 'start'),
                  stop: _attribute(start, 'stop'),
                  catchupId: _attribute(start, 'catchup-id'),
                );
              }
            } else if (name == 'icon' && channel != null) {
              channel.icon ??= _attribute(start, 'src');
            } else if (!start.isSelfClosing &&
                ((channel != null && name == 'display-name') ||
                    (programme != null && _programmeFields.contains(name)))) {
              field = name;
              buffer.clear();
            }
          case final XmlTextEvent text when field != null:
            buffer.write(text.value);
          case final XmlCDATAEvent data when field != null:
            buffer.write(data.value);
          case final XmlEndElementEvent end:
            final name = end.localName;
            if (field != null && name == field) {
              final value = buffer.toString().trim();
              if (value.isNotEmpty) {
                if (channel != null) {
                  channel.names.add(value);
                } else {
                  programme?.fields.putIfAbsent(name, () => value);
                }
              }
              field = null;
            } else if (name == 'channel' && channel != null) {
              if (channel.id case final id?) {
                channels.add(GuideChannel(id: id, displayNames: channel.names, iconUrl: channel.icon));
              }
              channel = null;
            } else if (name == 'programme' && programme != null) {
              if (programme.build() case final parsed?) programmes.add(parsed);
              programme = null;
            }
          default:
            break;
        }
      }
    } on XmlException catch (e) {
      throw FormatException('Invalid XMLTV: $e');
    }
    return ParsedGuide(channels: channels, programmes: programmes);
  }

  static String? _attribute(XmlStartElementEvent event, String name) {
    for (final attribute in event.attributes) {
      if (attribute.localName == name) {
        final value = attribute.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }
}

final _xmltvTime = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?\s*(?:([+-])(\d{2}):?(\d{2})|(Z))?$',
  caseSensitive: false,
);

/// An XMLTV time (`20260927200000 +0800`, `202609272000`, `+08:00`, `Z`) as
/// UTC; without a zone it is UTC. Null when malformed (3.x read only
/// `±hhmm` and treated `+08:00` as a bad time, dropping the programme).
DateTime? parseXmltvTime(String? text) {
  final match = _xmltvTime.firstMatch(text?.trim() ?? '');
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group) ?? '0');
  final month = part(2);
  final day = part(3);
  if (month < 1 || month > 12 || day < 1 || day > 31 || part(4) > 23 || part(5) > 59 || part(6) > 59) return null;
  final time = DateTime.utc(part(1), month, day, part(4), part(5), part(6));
  final sign = match.group(7);
  if (sign == null) return time;
  final offset = Duration(hours: part(8), minutes: part(9));
  return sign == '+' ? time.subtract(offset) : time.add(offset);
}

final class _Channel {
  new(this.id);

  final String? id;
  final names = <String>[];
  String? icon;
}

final class _Programme {
  new({required this.channel, required this.start, required this.stop, required this.catchupId});

  final String? channel;
  final String? start;
  final String? stop;
  final String? catchupId;
  final fields = <String, String>{};

  EpgProgramme? build() {
    final startTime = parseXmltvTime(start);
    final stopTime = parseXmltvTime(stop);
    final title = fields['title'];
    if (channel == null || startTime == null || stopTime == null || title == null) return null;
    return EpgProgramme(
      channelId: channel!,
      start: startTime,
      stop: stopTime,
      title: title,
      subtitle: fields['sub-title'],
      description: fields['desc'],
      category: fields['category'],
      episodeNum: fields['episode-num'],
      catchupId: catchupId,
    );
  }
}

/// Parses JSON guides:
/// 1. Standard format: `{"channels": [...], "programmes": [...]}`
/// 2. DIYP format: `{"date": "2026-11-17", "CCTV1": [{"start": "00:00", "end": "00:30", "title": "..."}]}`
/// 3. Data wrapper: `{"code": 200, "date": "...", "data": {"CCTV1": [...]}}` or `{"data": [...]}`
/// 4. Single-channel responses: `{"channel_name": "CCTV1", "date": "...", "epg_data": [...]}`
/// 5. Top-level arrays: `[{"channel": "CCTV1", "title": "...", "start": "..."}]` or `[{"id": "...", "programmes": [...]}]`
abstract final class JsonGuideParser {
  static const Set<String> _metadataKeys = {
    'code',
    'msg',
    'message',
    'status',
    'date',
    'time',
    'datetime',
    'success',
    'is_success',
    'total',
    'count',
    'version',
    'author',
    'url',
    'channels',
    'programmes',
    'epg',
    'events',
    'epg_data',
    'channel_name',
    'name',
    'id',
  };

  /// Parses [text].
  static ParsedGuide parse(String text) {
    var raw = text.trim();
    if (raw.startsWith('\uFEFF')) {
      raw = raw.substring(1).trim();
    }
    final decoded = jsonDecode(raw);
    final channels = <GuideChannel>[];
    final programmes = <EpgProgramme>[];
    final channelMap = <String, GuideChannel>{};

    void addChannel(GuideChannel ch) {
      if (ch.id.isNotEmpty && !channelMap.containsKey(ch.id)) {
        channelMap[ch.id] = ch;
        channels.add(ch);
      }
    }

    DateTime? baseDate;
    if (decoded is Map<String, Object?>) {
      baseDate = _parseDate(decoded['date'] ?? decoded['time'] ?? decoded['datetime']);
      if (baseDate == null && decoded['data'] is Map<String, Object?>) {
        final dataMap = decoded['data'] as Map<String, Object?>;
        baseDate = _parseDate(dataMap['date'] ?? dataMap['time'] ?? dataMap['datetime']);
      }
    }
    if (baseDate == null) {
      final now = DateTime.now();
      baseDate = DateTime(now.year, now.month, now.day);
    }

    if (decoded is Map<String, Object?>) {
      // 1. Explicit channels list
      if (decoded['channels'] case final List<Object?> list) {
        for (final item in list) {
          if (_channel(item) case final channel?) {
            addChannel(channel);
            if (item is Map<String, Object?>) {
              final subEpg = item['programmes'] ?? item['epg'] ?? item['events'] ?? item['epg_data'];
              if (subEpg is List) {
                _parseProgrammeList(channel.id, subEpg, baseDate, programmes);
              }
            }
          }
        }
      }

      // 2. Explicit programmes list
      if (decoded['programmes'] ?? decoded['epg'] ?? decoded['events'] case final List<Object?> list) {
        for (final item in list) {
          if (_programme(item, baseDate: baseDate) case final programme?) {
            programmes.add(programme);
          }
        }
      }

      // 3. Single-channel response with epg_data / data
      final chName = _text(decoded, const ['channel_name', 'channel', 'channelId']);
      final epgData = decoded['epg_data'] ?? (chName != null ? decoded['data'] : null);
      if (chName != null && epgData is List) {
        addChannel(GuideChannel(id: chName, displayNames: [chName]));
        _parseProgrammeList(chName, epgData, baseDate, programmes);
      }

      // 4. DIYP channel dictionary: {"CCTV1": [...], "CCTV2": [...]} or wrapped in "data"
      void parseChannelDictionary(Map<String, Object?> dict) {
        for (final entry in dict.entries) {
          final key = entry.key.trim();
          final val = entry.value;
          if (key.isNotEmpty && !_metadataKeys.contains(key.toLowerCase()) && val is List) {
            addChannel(GuideChannel(id: key, displayNames: [key]));
            _parseProgrammeList(key, val, baseDate!, programmes);
          }
        }
      }

      parseChannelDictionary(decoded);
      if (decoded['data'] is Map<String, Object?>) {
        parseChannelDictionary(decoded['data'] as Map<String, Object?>);
      } else if (decoded['data'] is List<Object?> && chName == null) {
        final dataList = decoded['data'] as List<Object?>;
        for (final item in dataList) {
          if (item is Map<String, Object?>) {
            if (_programme(item, baseDate: baseDate) case final p?) {
              programmes.add(p);
            } else if (_channel(item) case final ch?) {
              addChannel(ch);
              final subEpg = item['programmes'] ?? item['epg'] ?? item['events'] ?? item['epg_data'];
              if (subEpg is List) {
                _parseProgrammeList(ch.id, subEpg, baseDate, programmes);
              }
            }
          }
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, Object?>) {
          if (_programme(item, baseDate: baseDate) case final p?) {
            programmes.add(p);
          } else if (_channel(item) case final ch?) {
            addChannel(ch);
            final subEpg = item['programmes'] ?? item['epg'] ?? item['events'] ?? item['epg_data'];
            if (subEpg is List) {
              _parseProgrammeList(ch.id, subEpg, baseDate, programmes);
            }
          }
        }
      }
    }

    // Ensure every channel referenced in programmes exists in channels
    for (final prog in programmes) {
      if (prog.channelId.isNotEmpty && !channelMap.containsKey(prog.channelId)) {
        addChannel(GuideChannel(id: prog.channelId, displayNames: [prog.channelId]));
      }
    }

    return ParsedGuide(channels: channels, programmes: programmes);
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s.replaceAll('/', '-'));
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final ymd = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
    if (ymd != null) {
      return DateTime(int.parse(ymd.group(1)!), int.parse(ymd.group(2)!), int.parse(ymd.group(3)!));
    }
    return null;
  }

  static void _parseProgrammeList(
    String channelId,
    List<Object?> items,
    DateTime baseDate,
    List<EpgProgramme> target,
  ) {
    var dayOffset = 0;
    int? lastStartHour;

    final parsedItems = <({
      String title,
      DateTime start,
      DateTime? stop,
      String? desc,
      String? subTitle,
      String? category,
      String? episode,
      String? catchupId,
    })>[];

    for (final rawItem in items) {
      if (rawItem is! Map<String, Object?>) continue;
      final title = _text(rawItem, const ['title', 'name', 'programme', 't']);
      if (title == null || title.isEmpty) continue;

      final startRaw =
          rawItem['startTime'] ?? rawItem['start'] ?? rawItem['starttime'] ?? rawItem['time'] ?? rawItem['s'];
      if (startRaw == null) continue;

      if (startRaw is String) {
        final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(startRaw.trim());
        if (match != null) {
          final hour = int.parse(match.group(1)!);
          if (lastStartHour != null && hour < lastStartHour! - 12) {
            dayOffset++;
          }
          lastStartHour = hour;
        }
      }

      final startTime = _time(startRaw, baseDate: baseDate, dayOffset: dayOffset);
      if (startTime == null) continue;

      final stopRaw = rawItem['endTime'] ?? rawItem['end'] ?? rawItem['endtime'] ?? rawItem['stop'] ?? rawItem['e'];
      DateTime? stopTime;
      if (stopRaw != null) {
        var stopDayOffset = dayOffset;
        if (stopRaw is String) {
          final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(stopRaw.trim());
          if (match != null) {
            final stopHour = int.parse(match.group(1)!);
            if (stopHour < (lastStartHour ?? 0)) {
              stopDayOffset++;
            }
          }
        }
        stopTime = _time(stopRaw, baseDate: baseDate, dayOffset: stopDayOffset);
      }

      parsedItems.add((
        title: title,
        start: startTime,
        stop: stopTime,
        desc: _text(rawItem, const ['description', 'desc', 'summary', 'd']),
        subTitle: _text(rawItem, const ['subtitle', 'subTitle']),
        category: _text(rawItem, const ['category', 'genre']),
        episode: _text(rawItem, const ['episodeNum', 'episode']),
        catchupId: _text(rawItem, const ['catchupId', 'catchup-id', 'id']),
      ));
    }

    for (var i = 0; i < parsedItems.length; i++) {
      final item = parsedItems[i];
      final DateTime stop;
      if (item.stop != null && item.stop!.isAfter(item.start)) {
        stop = item.stop!;
      } else if (i + 1 < parsedItems.length && parsedItems[i + 1].start.isAfter(item.start)) {
        stop = parsedItems[i + 1].start;
      } else {
        stop = item.start.add(const Duration(minutes: 30));
      }

      target.add(
        EpgProgramme(
          channelId: channelId,
          start: item.start,
          stop: stop,
          title: item.title,
          description: item.desc,
          subtitle: item.subTitle,
          category: item.category,
          episodeNum: item.episode,
          catchupId: item.catchupId,
        ),
      );
    }
  }

  static String? _text(Map<String, Object?> item, List<String> keys) {
    for (final key in keys) {
      if (item[key] case final value?) {
        final s = value.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  static GuideChannel? _channel(Object? item) {
    if (item is! Map<String, Object?>) return null;
    final id = _text(item, const ['id', 'channelId', 'channel_id', 'channel', 'name']);
    if (id == null || id.isEmpty) return null;
    final displayName = _text(item, const ['displayName', 'name', 'title', 'channel_name']) ?? id;
    final displayNames = <String>[displayName];
    if (displayName != id) displayNames.add(id);
    return GuideChannel(
      id: id,
      displayNames: displayNames,
      iconUrl: _text(item, const ['icon', 'iconUrl', 'logo', 'tvg-logo']),
    );
  }

  static EpgProgramme? _programme(Object? item, {DateTime? baseDate}) {
    if (item is! Map<String, Object?>) return null;
    final channel = _text(item, const ['channelId', 'channel', 'channel_name', 'channel_id']);
    final title = _text(item, const ['title', 'name', 'programme', 't']);
    if (channel == null || channel.isEmpty || title == null || title.isEmpty) return null;
    final start = _time(
      item['startTime'] ?? item['start'] ?? item['starttime'] ?? item['time'] ?? item['s'],
      baseDate: baseDate,
    );
    if (start == null) return null;
    final duration = item['duration'];
    final stop =
        _time(
          item['endTime'] ?? item['end'] ?? item['endtime'] ?? item['stop'] ?? item['e'],
          baseDate: baseDate,
        ) ??
        start.add(Duration(minutes: duration is int ? duration : 30));
    return EpgProgramme(
      channelId: channel,
      start: start,
      stop: stop,
      title: title,
      description: _text(item, const ['description', 'desc', 'summary', 'd']),
      subtitle: _text(item, const ['subtitle', 'subTitle']),
      episodeNum: _text(item, const ['episodeNum', 'episode']),
      category: _text(item, const ['category', 'genre']),
      catchupId: _text(item, const ['catchupId', 'catchup-id', 'id']),
    );
  }

  static DateTime? _time(Object? value, {DateTime? baseDate, int dayOffset = 0}) {
    DateTime epoch(int number) =>
        DateTime.fromMillisecondsSinceEpoch(number < 10000000000 ? number * 1000 : number, isUtc: true);
    return switch (value) {
      final int number => epoch(number),
      final String text when RegExp(r'^(\d{10}|\d{13})$').hasMatch(text.trim()) => epoch(int.parse(text.trim())),
      final String text =>
        _parseTimeString(text.trim(), baseDate: baseDate, dayOffset: dayOffset) ??
            (int.tryParse(text.trim()) == null ? null : epoch(int.parse(text.trim()))),
      _ => null,
    };
  }

  static DateTime? _parseTimeString(String text, {DateTime? baseDate, int dayOffset = 0}) {
    final relMatch = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (relMatch != null) {
      final hour = int.parse(relMatch.group(1)!);
      final minute = int.parse(relMatch.group(2)!);
      final second = relMatch.group(3) != null ? int.parse(relMatch.group(3)!) : 0;
      final date = (baseDate ?? DateTime.now()).add(Duration(days: dayOffset));
      return DateTime(date.year, date.month, date.day, hour, minute, second);
    }

    final xmltv = parseXmltvTime(text);
    if (xmltv != null) return xmltv;

    final normalized = text.replaceAll('/', '-');
    return DateTime.tryParse(normalized) ?? DateTime.tryParse(normalized.replaceFirst(' ', 'T'));
  }
}
