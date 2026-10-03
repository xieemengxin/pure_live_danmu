import 'dart:convert';

import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';

/// The kinds of data Pure Live takes in from Simple Live's LAN sync.
enum SimpleLiveSyncKind { follows, shieldWords, bulletMagazine }

/// Site ids Simple Live writes into a follow entry; Pure Live uses the same
/// strings for these four platforms.
const Set<String> simpleLiveSiteIds = <String>{'bilibili', 'douyu', 'huya', 'douyin'};

/// Where accepted data goes. Kept behind an interface so the protocol can be
/// exercised without the app's stores.
abstract interface class SimpleLiveSyncSink {
  /// Adds the rooms not followed yet and returns how many were new.
  Future<int> addFollows(List<LiveRoom> rooms);

  /// Adds the words not present yet and returns how many were new.
  int addShieldWords(List<String> words);

  void setBulletMagazine(List<String> presets);
}

/// One accepted sync request, for the on-screen log.
class SimpleLiveSyncEvent {
  const SimpleLiveSyncEvent({required this.kind, required this.received, required this.added});

  final SimpleLiveSyncKind kind;

  /// Entries in the request that Pure Live could use.
  final int received;

  /// Entries that were new here.
  final int added;
}

class SimpleLiveSyncReply {
  const SimpleLiveSyncReply.ok() : status = true, message = 'success';
  const SimpleLiveSyncReply.refused(this.message) : status = false;

  final bool status;
  final String message;

  /// The sender only reads `status` and, on failure, shows `message`.
  Map<String, Object> toJson() => <String, Object>{'status': status, 'message': message};
}

/// The receiving side of Simple Live's LAN sync ("局域网同步"), as its sender
/// speaks it: JSON POSTs to fixed paths on TCP [httpPort], after a `GET /info`
/// handshake, optionally found through a UDP broadcast on [udpPort].
///
/// Everything accepted is merged. The sender's `overlay=1` ("覆盖远端数据")
/// would wipe the receiving list first; Pure Live follows far more platforms
/// than Simple Live knows, so it never deletes on a remote request.
class SimpleLiveSyncProtocol {
  SimpleLiveSyncProtocol({required this.sink, required this.accepts, this.onReceived});

  static const int httpPort = 23234;
  static const int udpPort = 23235;

  final SimpleLiveSyncSink sink;

  /// Whether the viewer currently lets this kind in.
  final bool Function(SimpleLiveSyncKind kind) accepts;
  final void Function(SimpleLiveSyncEvent event)? onReceived;

  /// `GET /info`. The sender requires `type`, `name`, `version` and `address`
  /// as strings and `port` as an integer, or it reports "连接失败".
  static Map<String, Object> info({
    required String id,
    required String type,
    required String name,
    required String version,
    required String address,
  }) => <String, Object>{
    'id': id,
    'type': type,
    'name': name,
    'version': version,
    'address': address,
    'port': httpPort,
  };

  /// The broadcast answering a sender's discovery probe, or null when
  /// [payload] is not a probe from another device.
  static String? discoveryReply(String payload, {required String id, required String type, required String name}) {
    final Object? probe;
    try {
      probe = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (probe is! Map || probe['type'] != 'hello' || probe['id'] == id) return null;
    return jsonEncode(<String, String>{'id': id, 'type': type, 'name': name});
  }

  Future<SimpleLiveSyncReply> handlePost(String path, String body) async {
    switch (path) {
      case '/sync/follow':
        return _receive(SimpleLiveSyncKind.follows, body, '关注列表', (json) async {
          if (json is! List) return null;
          final rooms = parseFollows(json);
          return (received: rooms.length, added: await sink.addFollows(rooms));
        });
      case '/sync/blocked_word':
        return _receive(SimpleLiveSyncKind.shieldWords, body, '弹幕屏蔽词', (json) async {
          if (json is! List) return null;
          final words = parseShieldWords(json);
          return (received: words.length, added: sink.addShieldWords(words));
        });
      case '/sync/bullet_magazine':
        return _receive(SimpleLiveSyncKind.bulletMagazine, body, '弹匣', (json) async {
          final presets = parseBulletMagazine(json);
          if (presets == null) return null;
          sink.setBulletMagazine(presets);
          final count = presets.where((preset) => preset.isNotEmpty).length;
          return (received: count, added: count);
        });
      case '/sync/tag':
        // The sender posts the follow list and its tag groups as a pair and
        // reports the whole sync as failed if this one is refused. Pure Live
        // has no equivalent grouping, so the groups are acknowledged and
        // dropped.
        return const SimpleLiveSyncReply.ok();
      case '/sync/history':
        return const SimpleLiveSyncReply.refused('Pure Live 不接收观看记录');
      case '/sync/account/bilibili':
        return const SimpleLiveSyncReply.refused('Pure Live 不接收账号信息');
      default:
        return const SimpleLiveSyncReply.refused('Pure Live 不支持这项同步');
    }
  }

  Future<SimpleLiveSyncReply> _receive(
    SimpleLiveSyncKind kind,
    String body,
    String label,
    Future<({int received, int added})?> Function(Object? json) take,
  ) async {
    if (!accepts(kind)) return SimpleLiveSyncReply.refused('Pure Live 没有开启接收$label');
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return SimpleLiveSyncReply.refused('$label的数据格式不正确');
    }
    final taken = await take(json);
    if (taken == null) return SimpleLiveSyncReply.refused('$label的数据格式不正确');
    onReceived?.call(SimpleLiveSyncEvent(kind: kind, received: taken.received, added: taken.added));
    return const SimpleLiveSyncReply.ok();
  }

  /// Simple Live's follow entries as rooms. Entries without a room id, or on a
  /// site Pure Live does not know, are left out.
  static List<LiveRoom> parseFollows(List<dynamic> entries) {
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final site = '${entry['siteId'] ?? ''}'.trim().toLowerCase();
      final roomId = '${entry['roomId'] ?? ''}'.trim();
      if (roomId.isEmpty || !simpleLiveSiteIds.contains(site) || !seen.add('$site:$roomId')) continue;
      rooms.add(
        LiveRoom(
          platform: site,
          roomId: roomId,
          nick: '${entry['userName'] ?? ''}'.trim(),
          avatar: '${entry['face'] ?? ''}'.trim(),
          // 没核实过开播状态，留给关注页的刷新去更新。
          liveStatus: LiveStatus.unknown,
        ),
      );
    }
    return rooms;
  }

  static List<String> parseShieldWords(Iterable<dynamic> values) {
    final words = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final word = '$value'.trim();
      if (word.isNotEmpty && seen.add(word)) words.add(word);
    }
    return words;
  }

  /// Six presets in Simple Live's direction order, which Pure Live shares.
  /// Simple Live stores them as a JSON array encoded into a string, so both
  /// that and a plain array are taken. Null when [value] is neither.
  static List<String>? parseBulletMagazine(Object? value) {
    Object? raw = value;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (raw is! List) return null;
    return DanmakuSettingsController.normalizeBulletMagazinePresets(raw);
  }
}
