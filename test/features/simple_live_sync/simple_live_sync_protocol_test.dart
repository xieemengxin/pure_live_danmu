import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/features/simple_live_sync/simple_live_sync_protocol.dart';
import 'package:pure_live/features/simple_live_sync/simple_live_sync_receiver.dart';

// 请求体的形状取自 Simple Live 发送端实际发出的 JSON（它的源码里各同步项的序列化）。
const List<Map<String, String>> _follows = [
  {
    'id': 'huya_660000',
    'roomId': '660000',
    'siteId': 'huya',
    'userName': '英雄联盟赛事',
    'face': 'https://example.com/a.png',
    'addTime': '2025-03-01 20:15:42.123456',
    'tag': '全部',
  },
  {
    'id': 'bilibili_21',
    'roomId': '21',
    'siteId': 'bilibili',
    'userName': 'B站官方',
    'face': '',
    'addTime': '2025-03-02 08:00:00.000',
  },
  {'id': 'kuaishou_1', 'roomId': '1', 'siteId': 'kuaishou', 'userName': '不认识的平台', 'face': ''},
];

/// 记下协议交给应用的数据；已有的关注和屏蔽词用来验证“只新增没有的”。
class _Sink implements SimpleLiveSyncSink {
  final Set<String> follows = {'huya:660000'};
  final Set<String> words = {'抽奖'};
  List<String>? magazine;

  @override
  Future<int> addFollows(List<LiveRoom> rooms) async =>
      rooms.where((room) => follows.add('${room.platform}:${room.roomId}')).length;

  @override
  int addShieldWords(List<String> incoming) => incoming.where(words.add).length;

  @override
  void setBulletMagazine(List<String> presets) => magazine = presets;
}

void main() {
  late _Sink sink;
  late Set<SimpleLiveSyncKind> accepted;
  late List<SimpleLiveSyncEvent> events;
  late SimpleLiveSyncProtocol protocol;

  setUp(() {
    sink = _Sink();
    accepted = SimpleLiveSyncKind.values.toSet();
    events = <SimpleLiveSyncEvent>[];
    protocol = SimpleLiveSyncProtocol(sink: sink, accepts: accepted.contains, onReceived: events.add);
  });

  test('关注列表：合并进来，只新增没关注过的，不认识的平台丢掉', () async {
    final reply = await protocol.handlePost('/sync/follow', jsonEncode(_follows));

    expect(reply.toJson(), {'status': true, 'message': 'success'});
    expect(sink.follows, {'huya:660000', 'bilibili:21'});
    expect(events.single.kind, SimpleLiveSyncKind.follows);
    expect(events.single.received, 2);
    expect(events.single.added, 1);
  });

  test('关注条目转成房间：昵称、头像带过来，开播状态待核实', () {
    final room = SimpleLiveSyncProtocol.parseFollows(_follows).first;
    expect(room.platform, 'huya');
    expect(room.roomId, '660000');
    expect(room.nick, '英雄联盟赛事');
    expect(room.avatar, 'https://example.com/a.png');
    expect(room.liveStatus, LiveStatus.unknown);
  });

  test('弹幕屏蔽词：合并，只新增没有的', () async {
    final reply = await protocol.handlePost('/sync/blocked_word', jsonEncode(['抽奖', r'/\d{6,}/', ' 代练 ', '']));

    expect(reply.status, isTrue);
    expect(sink.words, {'抽奖', r'/\d{6,}/', '代练'});
    expect(events.single.received, 3);
    expect(events.single.added, 2);
  });

  test('弹匣：六条预设，普通数组和 Simple Live 存的“字符串里的数组”都认', () async {
    expect((await protocol.handlePost('/sync/bullet_magazine', '["666","","牛"]')).status, isTrue);
    expect(sink.magazine, ['666', '', '牛', '', '', '']);

    await protocol.handlePost('/sync/bullet_magazine', jsonEncode('["a","b","c","d","e","f"]'));
    expect(sink.magazine, ['a', 'b', 'c', 'd', 'e', 'f']);
  });

  test('没开启接收的那一类：拒收并说明原因，数据不动', () async {
    accepted.remove(SimpleLiveSyncKind.follows);
    final reply = await protocol.handlePost('/sync/follow', jsonEncode(_follows));

    expect(reply.status, isFalse);
    expect(reply.message, contains('关注列表'));
    expect(sink.follows, {'huya:660000'});
    expect(events, isEmpty);

    // 其它开着的类别照常接收
    expect((await protocol.handlePost('/sync/blocked_word', '["x"]')).status, isTrue);
  });

  test('分组（标签）请求回成功但不保存：否则发送端会把整次关注同步报成失败', () async {
    expect((await protocol.handlePost('/sync/tag', '[{"id":"1","tag":"常看","userId":["huya_660000"]}]')).status, isTrue);
    expect(events, isEmpty);
  });

  test('观看记录、账号、未知路径：拒收', () async {
    for (final path in ['/sync/history', '/sync/account/bilibili', '/sync/whatever']) {
      final reply = await protocol.handlePost(path, '[]');
      expect(reply.status, isFalse, reason: path);
      expect(reply.message, isNotEmpty);
    }
  });

  test('数据不是预期的 JSON：拒收，不抛异常', () async {
    expect((await protocol.handlePost('/sync/follow', 'not json')).status, isFalse);
    expect((await protocol.handlePost('/sync/follow', '{"a":1}')).status, isFalse);
    expect((await protocol.handlePost('/sync/bullet_magazine', '42')).status, isFalse);
    expect(sink.follows, {'huya:660000'});
  });

  test('握手信息带齐发送端必须的字段和类型', () {
    final info = SimpleLiveSyncProtocol.info(
      id: 'abcd1234',
      type: 'ios',
      name: 'Pure Live',
      version: '3.1.17',
      address: '192.168.1.5',
    );
    final decoded = jsonDecode(jsonEncode(info)) as Map<String, dynamic>;

    for (final key in ['type', 'name', 'version', 'address']) {
      expect(decoded[key], isA<String>(), reason: key);
    }
    expect(decoded['port'], 23234);
  });

  test('发现广播：只回应别的设备发来的 hello', () {
    String? reply(String payload) =>
        SimpleLiveSyncProtocol.discoveryReply(payload, id: 'me', type: 'ios', name: 'Pure Live');

    expect(jsonDecode(reply('{"id":"other","type":"hello"}')!), {'id': 'me', 'type': 'ios', 'name': 'Pure Live'});
    expect(reply('{"id":"me","type":"hello"}'), isNull, reason: '自己发的不回');
    expect(reply('{"id":"other","type":"android","name":"x"}'), isNull, reason: '别人的应答不回');
    expect(reply('Who is SimpleLive?'), isNull);
  });

  test('真实 HTTP：发送端只认 200 加 JSON 类型的响应，失败也这样回', () async {
    final receiver = SimpleLiveSyncReceiver();
    receiver.acceptFollows.value = false;
    await receiver.start();
    addTearDown(receiver.onClose);
    expect(receiver.running.value, isTrue, reason: receiver.errorKey.value);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<({int status, String? type, Map<String, dynamic> body})> call(
      String method,
      String path, [
      String? body,
    ]) async {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${SimpleLiveSyncProtocol.httpPort}$path'),
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(body));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return (
        status: response.statusCode,
        type: response.headers.contentType?.mimeType,
        body: jsonDecode(text) as Map<String, dynamic>,
      );
    }

    final info = await call('GET', '/info');
    expect(info.status, 200);
    expect(info.type, 'application/json');
    expect(info.body['name'], 'Pure Live');
    expect(info.body['port'], 23234);
    expect(info.body['version'], isA<String>());

    // Simple Live 发关注时带 overlay 查询参数，请求体是 JSON 数组。
    final refused = await call('POST', '/sync/follow?overlay=1', jsonEncode(_follows));
    expect(refused.status, 200);
    expect(refused.type, 'application/json');
    expect(refused.body['status'], isFalse);
    expect(refused.body['message'], contains('关注列表'));

    final tag = await call('POST', '/sync/tag?overlay=1', '[]');
    expect(tag.body, {'status': true, 'message': 'success'});
  });
}
