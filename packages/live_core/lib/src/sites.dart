import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/source_descriptor.dart';

/// Platform ids, in the order 3.x listed its platforms (`Sites`).
abstract final class SiteIds {
  /// Bilibili.
  static const String bilibili = 'bilibili';

  /// Douyu.
  static const String douyu = 'douyu';

  /// Huya.
  static const String huya = 'huya';

  /// Douyin.
  static const String douyin = 'douyin';

  /// Kuaishou.
  static const String kuaishou = 'kuaishou';

  /// NetEase CC.
  static const String cc = 'cc';

  /// Twitch.
  static const String twitch = 'twitch';

  /// SOOP.
  static const String soop = 'soop';

  /// YY.
  static const String yy = 'yy';

  /// AcFun.
  static const String acfun = 'acfun';

  /// Picarto.
  static const String picarto = 'picarto';

  /// TwitCasting.
  static const String twitcasting = 'twitcasting';

  /// Missevan.
  static const String missevan = 'missevan';

  /// Inke.
  static const String inke = 'inke';

  /// Kilakila.
  static const String kilakila = 'kilakila';

  /// Xiaohongshu.
  static const String xiaohongshu = 'xiaohongshu';

  /// niconico.
  static const String niconico = 'niconico';

  /// Weibo.
  static const String weibo = 'weibo';

  /// SHOWROOM.
  static const String showroom = 'showroom';

  /// CHZZK.
  static const String chzzk = 'chzzk';

  /// Kick (retired in 3.2.11, back in v4: UPGRADES X-1).
  static const String kick = 'kick';

  /// LiveMe.
  static const String liveMe = 'liveme';

  /// TikTok LIVE.
  static const String tiktok = 'tiktok';

  /// YouTube Live.
  static const String youtube = 'youtube';

  /// Bigo Live.
  static const String bigo = 'bigo';

  /// PandaTV.
  static const String pandaLive = 'pandalive';

  /// FC2 Live.
  static const String fc2Live = 'fc2live';

  /// Steam Broadcasting.
  static const String steamBroadcast = 'steambroadcast';

  /// JD Live.
  static const String jdLive = 'jdlive';

  /// Kugou Live.
  static const String kugouLive = 'kugoulive';

  /// Baidu Live.
  static const String baiduLive = 'baidulive';

  /// Six Rooms.
  static const String sixRoom = 'sixroom';

  /// LOOK Live.
  static const String lookLive = 'looklive';

  /// 17LIVE.
  static const String seventeenLive = '17live';

  /// Huajiao (花椒直播).
  static const String huajiao = 'huajiao';

  /// OPENREC.tv.
  static const String openrec = 'openrec';

  /// Nimo TV.
  static const String nimotv = 'nimotv';

  /// Rumble.
  static const String rumble = 'rumble';

  /// Dailymotion.
  static const String dailymotion = 'dailymotion';

  /// Facebook Live.
  static const String facebook = 'facebook';

  /// DLive.
  static const String dlive = 'dlive';

  /// Vimeo Live.
  static const String vimeo = 'vimeo';

  /// Mirrativ.
  static const String mirrativ = 'mirrativ';

  /// Penguin Sports (企鹅体育).
  static const String qqSports = 'qqsports';

  /// CCTV / Migu public streams (央视频/咪咕公开流).
  static const String cctvLive = 'cctv_live';

  /// Wave Live (浪Live).
  static const String waveLive = 'wave_live';

  /// Pluto TV (FAST TV).
  static const String plutoTv = 'plutotv';

  /// Mixcloud Live.
  static const String mixcloud = 'mixcloud';

  /// Radiko.
  static const String radiko = 'radiko';

  /// ARD/ZDF Mediathek.
  static const String ardZdf = 'ard_zdf';

  /// NHK World.
  static const String nhkWorld = 'nhkworld';

  /// France 24.
  static const String france24 = 'france24';

  /// Al Jazeera.
  static const String alJazeera = 'aljazeera';

  /// Chaturbate (NSFW).
  static const String chaturbate = 'chaturbate';

  /// Stripchat (NSFW).
  static const String stripchat = 'stripchat';

  /// Bongacams (NSFW).
  static const String bongacams = 'bongacams';

  /// Cam4 (NSFW).
  static const String cam4 = 'cam4';

  /// MyFreeCams (NSFW).
  static const String myfreecams = 'myfreecams';

  /// Custom IPTV sources.
  static const String iptv = 'iptv';

  /// The search page's "all platforms" entry; not a platform.
  static const String all = 'all';

  /// Supported platforms, in display order.
  static const List<String> supported = [
    bilibili,
    douyu,
    huya,
    douyin,
    kuaishou,
    cc,
    twitch,
    soop,
    yy,
    acfun,
    picarto,
    twitcasting,
    missevan,
    inke,
    kilakila,
    xiaohongshu,
    niconico,
    weibo,
    showroom,
    chzzk,
    kick,
    liveMe,
    tiktok,
    youtube,
    bigo,
    pandaLive,
    fc2Live,
    steamBroadcast,
    jdLive,
    kugouLive,
    baiduLive,
    sixRoom,
    lookLive,
    seventeenLive,
    iptv,
  ];

  /// Voice platforms (A07.20): the stream's video track is a placeholder
  /// (Missevan's 16 × 16 picture) or a plain background (Kilakila's colour
  /// or picture), so the room shows its cover instead.
  static const Set<String> voiceLive = {missevan, kilakila};

  /// Platforms retired in 3.2.8 (hard to maintain, niche or unusable).
  /// Stored follows, history and links for them stay readable and are shown
  /// as retired instead of failing as unknown. Kick, retired in 3.2.11
  /// (Cloudflare refuses dart:io's TLS), is supported again (UPGRADES X-1,
  /// M4.34): its API goes through Android's system TLS.
  static const Set<String> retired = {
    'ttinglive',
    'popkontv',
    'shopeelive',
    'vkvideolive',
    'goodgame',
    'taobaolive',
  };

  /// Web hosts of the retired platforms, so a shared link is answered with
  /// "retired" instead of being ignored as unrecognised text.
  static const Set<String> retiredHosts = {
    'flextv.co.kr',
    'ttinglive.com',
    'popkontv.com',
    'goodgame.ru',
    'vkvideo.ru',
    'vkplay.live',
    'shopee.co.id',
    'taobao.com',
    'm.tb.cn',
  };

  /// Platforms whose room id is a user name that the platform itself matches
  /// without regard to case, so room identity ignores case there
  /// (`LiveRoom.identityKeyFor`; docs/E-直播平台/E05-平台框架和模型/E05.2-模型扩展/record.md). The room id
  /// keeps the spelling it was stored with; only comparisons fold it.
  ///
  /// - Twitch: the login name. Logins are lower case; the adapter requests
  ///   the lower-case form of any spelling (M4.8).
  /// - SOOP: the streamer id (BJ id). The platform answers it in lower case
  ///   and links are lower-cased (M4.7).
  /// - Picarto: the channel name. The platform finds a channel in any case
  ///   and answers its own spelling (`kaiyote`, `KAIYOTE` → `Kaiyote`, M4.11).
  /// - TwitCasting: the screen id. The adapter requests its lower-case form
  ///   (M4.12).
  /// - TikTok: the user name (`uniqueId`). The answer is matched in any case
  ///   and the adapter already lower-cases the room id (M4.22).
  /// - PandaTV: the login id. 3.x matched the room data in any case (M4.25).
  /// - Douyu: a rid or 靓号 (digits) or an alias. The room page redirects an
  ///   alias in any case to the same rid (`lpl`, `LPL`, `Lpl` → 288016,
  ///   M4.U.2).
  /// - Kuaishou: the user id. The room page finds a streamer in any case and
  ///   answers its own spelling (`kpl704668133` → `KPL704668133`,
  ///   `3X6B3WKUDIYPU2C` → `3x6b3wkudiypu2c`; M4.U.5, sample S13).
  /// - Bigo: the Bigo id. The studio finds a streamer's chosen id in any case
  ///   and answers its own spelling (`chrispcritter78`, `CHRISPCRITTER78` →
  ///   `ChrisPCritter78`, `QASHIA305` → `qashia305`; M4.U.24).
  /// - Kick: the channel slug. Kick's pages and API find a channel in any
  ///   case; the adapter requests and answers the lower-case slug (M4.34).
  ///
  /// Not included: numeric ids (case does not apply), YouTube video and
  /// channel ids (case-sensitive), niconico programme ids, CHZZK channel ids
  /// (hex the adapter already lower-cases), and ids whose case rule the
  /// platform has not shown: Huya aliases.
  static const Set<String> caseInsensitiveRoomIds = {
    twitch,
    soop,
    picarto,
    twitcasting,
    tiktok,
    pandaLive,
    douyu,
    kuaishou,
    bigo,
    kick,
  };

  /// Whether rooms of [platform] are identified without regard to the room
  /// id's case (see [caseInsensitiveRoomIds]).
  static bool ignoresRoomIdCase(String platform) => caseInsensitiveRoomIds.contains(platform.trim().toLowerCase());

  static final Set<String> _supported = supported.toSet();

  /// Whether [id] is a supported platform (case and spaces ignored).
  static bool isSupported(String id) => _supported.contains(id.trim().toLowerCase());

  /// Whether [id] is a retired platform.
  static bool isRetired(String id) => retired.contains(id.trim().toLowerCase());

  /// Whether [text] contains a link to a retired platform.
  static bool isRetiredLink(String text) {
    for (final match in RegExp(r'https?://[^\s]+', caseSensitive: false).allMatches(text)) {
      final host = Uri.tryParse(match.group(0)!)?.host.toLowerCase() ?? '';
      if (retiredHosts.any((root) => host == root || host.endsWith('.$root'))) return true;
    }
    return false;
  }

  /// Master metadata descriptors for all 55+ platforms according to Spec 2.0.
  static const Map<String, SourceDescriptor> descriptors = {
    // 1. 国内综合 / 游戏直播 (11)
    bilibili: SourceDescriptor(
      id: bilibili,
      name: '哔哩哔哩',
      region: SourceRegion.domestic,
      categories: {SourceCategory.game, SourceCategory.entertainment, SourceCategory.lifestyle},
      networkMode: NetworkMode.direct,
      isNative: true,
      websiteUrl: 'https://live.bilibili.com',
      aliases: ['b站', 'bz', 'bili', 'bilibili'],
    ),
    douyu: SourceDescriptor(
      id: douyu,
      name: '斗鱼',
      region: SourceRegion.domestic,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      isNative: true,
      websiteUrl: 'https://www.douyu.com',
      aliases: ['dy', 'douyu'],
    ),
    huya: SourceDescriptor(
      id: huya,
      name: '虎牙',
      region: SourceRegion.domestic,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      isNative: true,
      websiteUrl: 'https://www.huya.com',
      aliases: ['hy', 'huya'],
    ),
    douyin: SourceDescriptor(
      id: douyin,
      name: '抖音',
      region: SourceRegion.domestic,
      categories: {SourceCategory.entertainment, SourceCategory.lifestyle},
      networkMode: NetworkMode.direct,
      isNative: true,
      websiteUrl: 'https://live.douyin.com',
      aliases: ['dy', 'douyin'],
    ),
    kuaishou: SourceDescriptor(
      id: kuaishou,
      name: '快手',
      region: SourceRegion.domestic,
      categories: {SourceCategory.entertainment, SourceCategory.lifestyle},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://live.kuaishou.com',
      aliases: ['ks', 'kuaishou'],
    ),
    cc: SourceDescriptor(
      id: cc,
      name: '网易CC',
      region: SourceRegion.domestic,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://cc.163.com',
      aliases: ['cc', '163', 'netease'],
    ),
    yy: SourceDescriptor(
      id: yy,
      name: 'YY直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.entertainment, SourceCategory.audio},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://www.yy.com',
      aliases: ['yy'],
    ),
    xiaohongshu: SourceDescriptor(
      id: xiaohongshu,
      name: '小红书',
      region: SourceRegion.domestic,
      categories: {SourceCategory.lifestyle, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://www.xiaohongshu.com',
      aliases: ['xhs', 'red'],
    ),
    weibo: SourceDescriptor(
      id: weibo,
      name: '微博直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.news, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://weibo.com',
      aliases: ['wb', 'weibo'],
    ),
    baiduLive: SourceDescriptor(
      id: baiduLive,
      name: '百度直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.lifestyle, SourceCategory.news},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://live.baidu.com',
      aliases: ['bd', 'baidu'],
    ),
    jdLive: SourceDescriptor(
      id: jdLive,
      name: '京东直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.lifestyle},
      networkMode: NetworkMode.direct,
      websiteUrl: 'https://jvod.300.cn',
      aliases: ['jd', 'jingdong'],
    ),

    // 2. 国内泛娱乐 / 语音 / 体育 (10)
    kugouLive: SourceDescriptor(
      id: kugouLive,
      name: '酷狗繁星',
      region: SourceRegion.domestic,
      categories: {SourceCategory.audio, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['kg', 'kugou', 'fanxing'],
    ),
    sixRoom: SourceDescriptor(
      id: sixRoom,
      name: '六间房',
      region: SourceRegion.domestic,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['6room', 'sixroom'],
    ),
    huajiao: SourceDescriptor(
      id: huajiao,
      name: '花椒直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['hj', 'huajiao'],
    ),
    inke: SourceDescriptor(
      id: inke,
      name: '映客直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['yk', 'inke'],
    ),
    missevan: SourceDescriptor(
      id: missevan,
      name: '猫耳FM',
      region: SourceRegion.domestic,
      categories: {SourceCategory.audio},
      networkMode: NetworkMode.direct,
      aliases: ['missevan', 'maoer'],
    ),
    kilakila: SourceDescriptor(
      id: kilakila,
      name: '克拉克拉',
      region: SourceRegion.domestic,
      categories: {SourceCategory.audio, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['kila', 'hongdou'],
    ),
    qqSports: SourceDescriptor(
      id: qqSports,
      name: '企鹅体育',
      region: SourceRegion.domestic,
      categories: {SourceCategory.sports},
      networkMode: NetworkMode.direct,
      aliases: ['qqsports', 'penguin', 'qie'],
    ),
    cctvLive: SourceDescriptor(
      id: cctvLive,
      name: '央视频/咪咕公开流',
      region: SourceRegion.domestic,
      categories: {SourceCategory.sports, SourceCategory.news, SourceCategory.fastTv},
      networkMode: NetworkMode.direct,
      aliases: ['cctv', 'migu', 'yangshipin'],
    ),
    acfun: SourceDescriptor(
      id: acfun,
      name: 'AcFun',
      region: SourceRegion.domestic,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['ac', 'acfun', 'a站'],
    ),
    lookLive: SourceDescriptor(
      id: lookLive,
      name: 'LOOK直播',
      region: SourceRegion.domestic,
      categories: {SourceCategory.audio, SourceCategory.entertainment},
      networkMode: NetworkMode.direct,
      aliases: ['look', '163look'],
    ),

    // 3. 国际综合 / 电竞头部 (10)
    twitch: SourceDescriptor(
      id: twitch,
      name: 'Twitch',
      region: SourceRegion.international,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      isNative: true,
      aliases: ['tw', 'twitch'],
    ),
    youtube: SourceDescriptor(
      id: youtube,
      name: 'YouTube Live',
      region: SourceRegion.international,
      categories: {SourceCategory.game, SourceCategory.news, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      isNative: true,
      aliases: ['yt', 'youtube', '油管'],
    ),
    kick: SourceDescriptor(
      id: kick,
      name: 'Kick',
      region: SourceRegion.international,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['kick'],
    ),
    tiktok: SourceDescriptor(
      id: tiktok,
      name: 'TikTok Live',
      region: SourceRegion.international,
      categories: {SourceCategory.entertainment, SourceCategory.lifestyle},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['tt', 'tiktok'],
    ),
    facebook: SourceDescriptor(
      id: facebook,
      name: 'Facebook Live',
      region: SourceRegion.international,
      categories: {SourceCategory.lifestyle, SourceCategory.news},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['fb', 'facebook'],
    ),
    rumble: SourceDescriptor(
      id: rumble,
      name: 'Rumble',
      region: SourceRegion.international,
      categories: {SourceCategory.news, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['rumble'],
    ),
    dlive: SourceDescriptor(
      id: dlive,
      name: 'DLive',
      region: SourceRegion.international,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['dlive'],
    ),
    vimeo: SourceDescriptor(
      id: vimeo,
      name: 'Vimeo Live',
      region: SourceRegion.international,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['vimeo'],
    ),
    steamBroadcast: SourceDescriptor(
      id: steamBroadcast,
      name: 'Steam.tv',
      region: SourceRegion.international,
      categories: {SourceCategory.game},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['steam', 'steamtv'],
    ),
    dailymotion: SourceDescriptor(
      id: dailymotion,
      name: 'Dailymotion',
      region: SourceRegion.international,
      categories: {SourceCategory.news, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['dm', 'dailymotion'],
    ),

    // 4. 日韩 / 东南亚主流 (12)
    chzzk: SourceDescriptor(
      id: chzzk,
      name: 'CHZZK (Naver)',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['cz', 'chzzk', 'naver'],
    ),
    soop: SourceDescriptor(
      id: soop,
      name: 'SOOP (AfreecaTV)',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['soop', 'afreeca'],
    ),
    niconico: SourceDescriptor(
      id: niconico,
      name: 'Niconico Live',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['nico', 'niconico', 'n站'],
    ),
    twitcasting: SourceDescriptor(
      id: twitcasting,
      name: 'TwitCasting',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.audio, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['twitcasting', 'cas'],
    ),
    showroom: SourceDescriptor(
      id: showroom,
      name: 'SHOWROOM',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['sr', 'showroom'],
    ),
    openrec: SourceDescriptor(
      id: openrec,
      name: 'OPENREC.tv',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.game},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['openrec'],
    ),
    mirrativ: SourceDescriptor(
      id: mirrativ,
      name: 'Mirrativ',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.game},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['mirrativ'],
    ),
    fc2Live: SourceDescriptor(
      id: fc2Live,
      name: 'FC2 Live',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['fc2'],
    ),
    bigo: SourceDescriptor(
      id: bigo,
      name: 'Bigo Live',
      region: SourceRegion.southeastAsia,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['bigo'],
    ),
    nimotv: SourceDescriptor(
      id: nimotv,
      name: 'NimoTV',
      region: SourceRegion.southeastAsia,
      categories: {SourceCategory.game, SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['nimo'],
    ),
    waveLive: SourceDescriptor(
      id: waveLive,
      name: '浪Live',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['lang', 'wavelive'],
    ),
    seventeenLive: SourceDescriptor(
      id: seventeenLive,
      name: '17LIVE',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.entertainment},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['17', '17live'],
    ),

    // 5. 海外公开电台 / 免费 FAST TV (7)
    plutoTv: SourceDescriptor(
      id: plutoTv,
      name: 'Pluto TV',
      region: SourceRegion.international,
      categories: {SourceCategory.fastTv, SourceCategory.news},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['pluto', 'plutotv'],
    ),
    mixcloud: SourceDescriptor(
      id: mixcloud,
      name: 'Mixcloud Live',
      region: SourceRegion.international,
      categories: {SourceCategory.audio},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['mixcloud'],
    ),
    radiko: SourceDescriptor(
      id: radiko,
      name: 'Radiko',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.audio},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['radiko'],
    ),
    ardZdf: SourceDescriptor(
      id: ardZdf,
      name: 'ARD/ZDF Mediathek',
      region: SourceRegion.international,
      categories: {SourceCategory.fastTv, SourceCategory.news},
      networkMode: NetworkMode.proxyRequired,
      aliases: ['ard', 'zdf'],
    ),
    nhkWorld: SourceDescriptor(
      id: nhkWorld,
      name: 'NHK World',
      region: SourceRegion.eastAsia,
      categories: {SourceCategory.fastTv, SourceCategory.news},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['nhk'],
    ),
    france24: SourceDescriptor(
      id: france24,
      name: 'France 24',
      region: SourceRegion.international,
      categories: {SourceCategory.fastTv, SourceCategory.news},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['france24'],
    ),
    alJazeera: SourceDescriptor(
      id: alJazeera,
      name: 'Al Jazeera',
      region: SourceRegion.international,
      categories: {SourceCategory.fastTv, SourceCategory.news},
      networkMode: NetworkMode.proxyRecommended,
      aliases: ['aljazeera'],
    ),

    // 6. IPTV 电视 (1)
    iptv: SourceDescriptor(
      id: iptv,
      name: 'IPTV 网络电视',
      region: SourceRegion.domestic,
      categories: {SourceCategory.fastTv, SourceCategory.news, SourceCategory.sports},
      networkMode: NetworkMode.direct,
      aliases: ['iptv', 'tv', 'cctv', 'dianshi'],
    ),

    // 7. 成人独立扩展源 (仅通过外部签名插件加载)
    chaturbate: SourceDescriptor(
      id: chaturbate,
      name: 'Chaturbate',
      region: SourceRegion.international,
      categories: {SourceCategory.adult},
      networkMode: NetworkMode.proxyRequired,
      isNsfw: true,
      aliases: ['cb', 'chaturbate'],
    ),
    stripchat: SourceDescriptor(
      id: stripchat,
      name: 'Stripchat',
      region: SourceRegion.international,
      categories: {SourceCategory.adult},
      networkMode: NetworkMode.proxyRequired,
      isNsfw: true,
      aliases: ['stripchat'],
    ),
    bongacams: SourceDescriptor(
      id: bongacams,
      name: 'BongaCams',
      region: SourceRegion.international,
      categories: {SourceCategory.adult},
      networkMode: NetworkMode.proxyRequired,
      isNsfw: true,
      aliases: ['bongacams'],
    ),
    cam4: SourceDescriptor(
      id: cam4,
      name: 'Cam4',
      region: SourceRegion.international,
      categories: {SourceCategory.adult},
      networkMode: NetworkMode.proxyRequired,
      isNsfw: true,
      aliases: ['cam4'],
    ),
    myfreecams: SourceDescriptor(
      id: myfreecams,
      name: 'MyFreeCams',
      region: SourceRegion.international,
      categories: {SourceCategory.adult},
      networkMode: NetworkMode.proxyRequired,
      isNsfw: true,
      aliases: ['mfc', 'myfreecams'],
    ),
  };

  /// Returns the descriptor of [platformId], or a generated fallback if undefined.
  static SourceDescriptor descriptorOf(String platformId) {
    final key = platformId.trim().toLowerCase();
    return descriptors[key] ?? SourceDescriptor.fallback(id: key, name: platformId);
  }
}

/// One adapter per platform, created on first use and then kept.
///
/// 3.x built all 34 adapters on every read of `Sites.supportSites` and a
/// fresh adapter on every `Sites.of`, which threw away per-platform session
/// caches (Kuaishou's session cookie, for example) on each lookup.
final class SiteRegistry {
  /// A registry that builds adapters with [factories], keyed by platform id.
  /// Only supported ids are listed; the order is [SiteIds.supported].
  new(Map<String, LiveSite Function()> factories) : _factories = Map.unmodifiable(factories);

  final Map<String, LiveSite Function()> _factories;
  final Map<String, LiveSite> _sites = {};

  /// Platform ids with an adapter, in display order.
  List<String> get ids => [
    for (final id in SiteIds.supported)
      if (_factories.containsKey(id)) id,
  ];

  /// Every adapter, in display order.
  List<LiveSite> get sites => [for (final id in ids) of(id)];

  /// The adapter of [id] (case and spaces ignored); throws [ArgumentError]
  /// for a platform without one.
  LiveSite of(String id) => maybeOf(id) ?? (throw ArgumentError.value(id, 'id', 'Unsupported live site'));

  /// The adapter of [id], or null.
  LiveSite? maybeOf(String id) {
    final key = id.trim().toLowerCase();
    final existing = _sites[key];
    if (existing != null) return existing;
    final factory = _factories[key];
    if (factory == null) return null;
    return _sites[key] = factory();
  }

  /// The platforms of the user's platform list [saved] (the "hot areas"
  /// setting) that have an adapter, in the saved order without duplicates.
  List<String> availableIds(Iterable<String> saved) {
    final seen = <String>{};
    return [
      for (final raw in saved)
        if (raw.trim().toLowerCase() case final id when seen.add(id) && _factories.containsKey(id)) id,
    ];
  }
}
