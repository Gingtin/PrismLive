import 'package:live_core/live_core.dart';
import 'package:live_iptv/src/guide/matcher.dart';
import 'package:live_iptv/src/importer.dart';
import 'package:live_iptv/src/library.dart';
import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/m3u_parser.dart';
import 'package:live_iptv/src/playlist/txt_parser.dart';

/// The IPTV platform (3.x `IptvSite`): imported playlists shown like a live
/// platform.
///
/// - Categories are the playlists (the built-in hot one excepted); their
///   areas are the channels, and a channel's area opens its room directly.
/// - Recommendations are the playlist chosen for them ([popularPlaylistId],
///   [shownIptvPlaylist]); by default the hot playlist, imported on first
///   use unless it was deleted ([hotRemoved]; 3.x imported it again on every
///   visit, so it could not be deleted).
/// - Search matches channel names.
/// - A room is one channel: always live, one quality `默认` (`default`)
///   with the channel URL; the room carries the catch-up attributes, the
///   stream's request headers and, with a selected guide, the guide channel
///   and the programme on air.
/// - Lists are not paged: page 1 holds everything and later pages are empty
///   (3.x returned the whole list for every page).
final class IptvSite extends LiveSite implements LiveSiteRecordRoomResolver {
  /// Creates the platform.
  new({
    required this.library,
    required this.importer,
    required this.selectedGuideSourceId,
    this.popularPlaylistId = _none,
    this.hotRemoved = _kept,
    this.now = DateTime.now,
  });

  static String _none() => '';
  static bool _kept() => false;

  /// Storage.
  final IptvLibrary library;

  /// Imports the hot playlist on first use.
  final IptvImporter importer;

  /// The selected guide source id (3.x setting `selectedSourceId`).
  final String Function() selectedGuideSourceId;

  /// The playlist the recommendations show; empty for the hot playlist.
  final String Function() popularPlaylistId;

  /// Whether the hot playlist was deleted (it is not imported again).
  final bool Function() hotRemoved;

  /// Clock for the programme on air.
  final DateTime Function() now;

  static final RegExp _lineSuffix =
      RegExp(r'\s*[-_]?\s*[\(\[（【]?(?:线路|Line)\s*\d+[\)\]）】]?\s*$', caseSensitive: false);

  /// Strips line suffix such as `(线路1)`, `（线路2）`, `【线路3】`, `(Line 1)` to find the common channel base name.
  static String channelBaseName(String name) {
    final stripped = name.replaceAll(_lineSuffix, '').trim();
    return stripped.isEmpty ? name.trim() : stripped;
  }

  /// Deduplicates channels that share the same base name within a group and playlist.
  static List<IptvChannel> _deduplicateChannels(List<IptvChannel> channels) {
    final seen = <String>{};
    final result = <IptvChannel>[];
    for (final channel in channels) {
      final base = channelBaseName(channel.name);
      final key = '${channel.playlistId}::${channel.entry.groupTitle ?? ''}::$base';
      if (seen.add(key)) {
        result.add(channel);
      }
    }
    return result;
  }

  static const List<String> _offAirKeywords = [
    '休台',
    '停播',
    '非播出时段',
    '检修',
    '维护',
    '测试卡',
    '彩条',
    '未开播',
    '停止播出',
    '暂停播出',
    '无信号',
    '节目已结束',
    'off-air',
    'off air',
  ];

  /// Checks if an EPG programme title indicates that the broadcast is off-air.
  static bool isOffAirProgramme(String? title) {
    if (title == null || title.trim().isEmpty) return false;
    final lower = title.toLowerCase();
    return _offAirKeywords.any(lower.contains);
  }

  /// The quality id of the single quality.
  static const String qualityId = 'default';

  @override
  String get id => SiteIds.iptv;

  @override
  String get name => '网络';

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page > 1) return const [];
    return [
      for (final playlist in await library.playlists())
        if (!playlist.isHot)
          LiveCategory(
            id: playlist.id,
            name: playlist.name,
            children: [
              for (final channel in _deduplicateChannels(await library.channels(playlist.id)))
                LiveArea(
                  platform: id,
                  areaType: playlist.id,
                  typeName: playlist.name,
                  areaId: channel.id,
                  areaName: channelBaseName(channel.name),
                  areaPic: channel.entry.tvgLogo ?? '',
                ),
            ],
          ),
    ];
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page > 1) return const [];
    final channel = await library.channel(category.areaId);
    if (channel == null) return const [];
    final guide = await _guide(channel);
    return [
      _room(
        channel,
        nick: channel.entry.groupTitle ?? '',
        title: channelBaseName(channel.name),
        guide: guide,
      ),
    ];
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page > 1) return const [];
    final id = shownIptvPlaylist(await library.playlists(), wanted: popularPlaylistId(), hotRemoved: hotRemoved());
    if (id == null) return const [];
    return id == IptvPlaylist.hotId ? await hotRooms() : await _playlistRooms(id);
  }

  /// The hot playlist's channels as rooms, imported on first use; none when
  /// it was deleted.
  Future<List<LiveRoom>> hotRooms() async {
    if (hotRemoved()) return const [];
    var channels = await library.channels(IptvPlaylist.hotId);
    if (channels.isEmpty) {
      await importer.loadHotPlaylist(hotRemoved: hotRemoved);
      channels = await library.channels(IptvPlaylist.hotId);
    }
    if (hotRemoved()) return const [];
    final dedup = _deduplicateChannels(channels);
    final guides = await _guidesForChannels(dedup);
    return [
      for (final channel in dedup)
        _room(
          channel,
          nick: channel.entry.groupTitle ?? '',
          title: channelBaseName(channel.name),
          introduction: channel.name,
          guide: guides[channel.id],
        ),
    ];
  }

  Future<List<LiveRoom>> _playlistRooms(String id) async {
    final channels = _deduplicateChannels(await library.channels(id));
    final guides = await _guidesForChannels(channels);
    return [
      for (final channel in channels)
        _room(
          channel,
          nick: channel.entry.groupTitle ?? '',
          title: channelBaseName(channel.name),
          introduction: channel.name,
          guide: guides[channel.id],
        ),
    ];
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    if (page > 1 || keyword.trim().isEmpty) return const [];
    final matches = _deduplicateChannels(await library.searchChannels(keyword));
    final guides = await _guidesForChannels(matches);
    return [
      for (final channel in matches)
        _room(
          channel,
          nick: channel.entry.groupTitle ?? '',
          title: channelBaseName(channel.name),
          guide: guides[channel.id],
        ),
    ];
  }

  /// The room of channel [roomId]. A room id that is itself a stream URL
  /// (3.x played such ids as they are) gives a room playing that URL; any
  /// other unknown id is [NotFound] (3.x returned an empty "live" room that
  /// failed only when played).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    final channel = await library.channel(roomId);
    if (channel == null) {
      final url = roomId.trim();
      if (!isSupportedStreamUrl(url, {...M3uParser.schemes, ...TxtParser.schemes})) throw NotFound(id, roomId);
      return LiveRoom(roomId: roomId, platform: id, link: url, data: url, watching: '', liveStatus: LiveStatus.live);
    }
    final guide = await _guide(channel);
    return _room(
      channel,
      nick: channel.entry.tvgName ?? channel.name,
      title: channelBaseName(channel.name),
      guide: guide,
    );
  }

  /// The stored channel is authoritative, so the recording detail is the
  /// room detail.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => getRoomDetail(roomId: roomId);

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final primaryUrl = detail.data?.toString().trim() ?? '';
    if (primaryUrl.isEmpty) return const [];
    final urls = <String>[primaryUrl];
    final channel = await library.channel(detail.roomId);
    if (channel != null) {
      final base = channelBaseName(channel.name);
      if (base.isNotEmpty) {
        final allChannels = await library.channels(channel.playlistId);
        for (final other in allChannels) {
          if (other.id != channel.id && channelBaseName(other.name) == base) {
            final u = other.entry.streamUrl.trim();
            if (u.isNotEmpty && !urls.contains(u)) {
              urls.add(u);
            }
          }
        }
      }
    }
    return [
      LivePlayQuality(quality: '默认', id: qualityId, sort: 1, data: urls),
    ];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = quality.data;
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item.toString().trim() case final url when url.isNotEmpty) url,
    ];
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final channel = await library.channel(roomId);
    if (channel != null) {
      final guide = await _guide(channel);
      if (isOffAirProgramme(guide?.programme?.title)) return false;
    }
    return true;
  }

  Future<Map<String, ({String key, EpgProgramme? programme})>> _guidesForChannels(List<IptvChannel> channels) async {
    final sourceId = selectedGuideSourceId();
    if (sourceId.isEmpty || channels.isEmpty) return const {};
    final guideChannels = await library.guideChannels(sourceId);
    final playlistIds = {for (final c in channels) c.playlistId};
    final mappingsByPlaylist = <String, List<EpgMapping>>{};
    for (final pid in playlistIds) {
      mappingsByPlaylist[pid] = await library.mappings(pid);
    }
    final channelKeys = <String, String>{};
    for (final channel in channels) {
      final mappings = mappingsByPlaylist[channel.playlistId] ?? const [];
      final key = resolveGuideChannel(
        channel: channel,
        sourceId: sourceId,
        guideChannels: guideChannels,
        mapping: mappings.where((m) => m.channelId == channel.id).firstOrNull,
      );
      if (key != null) {
        channelKeys[channel.id] = key;
      }
    }
    if (channelKeys.isEmpty) return const {};
    final onAir = await library.programmesAt(channelKeys.values.toSet(), now());
    final progByKey = <String, EpgProgramme>{};
    for (final prog in onAir) {
      progByKey.putIfAbsent(prog.channelKey, () => prog);
    }
    return {
      for (final entry in channelKeys.entries)
        entry.key: (key: entry.value, programme: progByKey[entry.value]),
    };
  }

  Future<({String key, EpgProgramme? programme})?> _guide(IptvChannel channel) async =>
      (await _guidesForChannels([channel]))[channel.id];

  LiveRoom _room(
    IptvChannel channel, {
    required String nick,
    String? title,
    ({String key, EpgProgramme? programme})? guide,
    String? introduction,
  }) {
    final entry = channel.entry;
    final progTitle = guide?.programme?.title;
    final isOffAir = isOffAirProgramme(progTitle);
    final displayTitle = title ?? entry.name;
    final logo = entry.tvgLogo ?? '';
    return LiveRoom(
      roomId: channel.id,
      platform: id,
      title: displayTitle,
      nick: nick,
      avatar: logo,
      cover: logo,
      area: entry.groupTitle ?? '',
      watching: '',
      liveStatus: isOffAir ? LiveStatus.offline : LiveStatus.live,
      introduction: introduction,
      link: entry.streamUrl,
      data: entry.streamUrl,
      epgId: guide?.key,
      currentProgramme: progTitle,
      currentProgrammeDescription: guide?.programme?.description,
      catchUp: CatchUp(
        mode: entry.catchupMode,
        source: entry.catchupSource,
        days: entry.catchupDays,
        correctionHours: entry.catchupCorrectionHours,
      ),
      httpHeaders: entry.httpHeaders,
    );
  }
}

/// The playlist the recommendations show (V02.9): [wanted] while it is one
/// of [playlists] (the hot one only while not [hotRemoved]); otherwise the
/// hot playlist unless it was deleted (it need not be imported yet); then
/// the first imported playlist in [compareIptvPlaylists] order; null when
/// there is none.
String? shownIptvPlaylist(Iterable<IptvPlaylist> playlists, {required String wanted, required bool hotRemoved}) {
  if (wanted.isNotEmpty && playlists.any((playlist) => playlist.id == wanted && !(playlist.isHot && hotRemoved))) {
    return wanted;
  }
  if (!hotRemoved) return IptvPlaylist.hotId;
  final imported = [
    for (final playlist in playlists)
      if (!playlist.isHot) playlist,
  ]..sort(compareIptvPlaylists);
  return imported.firstOrNull?.id;
}

/// The order of imported playlists on screen (3.x `iptv_manage.dart:117-124`):
/// network ones first, then by name, ignoring case.
int compareIptvPlaylists(IptvPlaylist a, IptvPlaylist b) =>
    a.isRemote != b.isRemote ? (a.isRemote ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase());
