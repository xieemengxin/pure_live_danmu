import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';
import 'package:pure_live/core/tars/codec/tars_struct.dart';
import 'package:pure_live/core/tars/tup/tars_uni_packet.dart';
import 'package:pure_live/shared/platforms/huya/huya_danmaku.dart';
import 'package:pure_live/shared/platforms/huya/huya_send_message.dart';
import 'package:pure_live/shared/platforms/live_danmaku_sender.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const int _viewerUid = 20240001;
const String _loggedInCookie = 'yyuid=$_viewerUid; guid=0123456789abcdef0123456789abcdef; udb_passdata=3';
const int _presenterUid = 5550001;
const int _topSid = 77700001;
const int _subSid = 77700002;

/// 代替真实 WebSocket：记下引擎发出的帧，测试往里塞服务端的帧。
class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _FakeChannel(this.endpoint);

  final String endpoint;
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<Uint8List> sent = <Uint8List>[];
  late final _FakeSink _sink = _FakeSink(this);

  /// 引擎发出的 `sendMessage` 请求帧（外层命令 3），不含进房和心跳。
  List<Uint8List> get sendRequests => sent.where((frame) => TarsInputStream(frame).read(0, 0, false) == 3).toList();

  @override
  Future<void> get ready => Future<void>.value();
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) => _channel.sent.add(Uint8List.fromList(data as List<int>));
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
    if (!_channel.incoming.isClosed) await _channel.incoming.close();
  }

  @override
  Future<void> get done => _done.future;
}

class _BulletFormat extends TarsStruct {
  @override
  void writeTo(TarsOutputStream os) {
    os.write(-1, 0);
    os.write(4, 1);
    os.write(0, 2);
    os.write(1, 3);
  }

  @override
  void readFrom(TarsInputStream inputStream) {}
  @override
  Object deepCopy() => _BulletFormat();
  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class _Sender extends TarsStruct {
  _Sender(this.uid, this.nick);
  final int uid;
  final String nick;

  @override
  void writeTo(TarsOutputStream os) {
    os.write(uid, 0);
    os.write(nick, 2);
  }

  @override
  void readFrom(TarsInputStream inputStream) {}
  @override
  Object deepCopy() => _Sender(uid, nick);
  @override
  void displayAsString(StringBuffer sb, int level) {}
}

/// 服务端推来的一条聊天消息（外层命令 7，`uri 1400`）。
Uint8List _chatPush({required int senderUid, required String content}) {
  final message = TarsOutputStream()
    ..write(_Sender(senderUid, '观众$senderUid'), 0)
    ..write(content, 3)
    ..write(_BulletFormat(), 6);
  final push = TarsOutputStream()
    ..write(5, 0)
    ..write(1400, 1)
    ..write(message.toUint8List(), 2);
  final frame = TarsOutputStream()
    ..write(7, 0)
    ..write(push.toUint8List(), 1);
  return frame.toUint8List();
}

/// 服务端对某条 `sendMessage` 的回应（外层命令 4）；[returned] 是函数返回值，0 为成功。
Uint8List _sendReply({required int requestId, int returned = 0}) {
  final packet = TarsUniPacket()
    ..setTarsVersion(3)
    ..requestId = requestId
    ..servantName = 'liveui'
    ..funcName = 'sendMessage'
    ..put('tRsp', 0);
  packet.newData[''] = (TarsOutputStream()..write(returned, 0)).toUint8List();
  final frame = TarsOutputStream()
    ..write(4, 0)
    ..write(packet.encode(), 1);
  return frame.toUint8List();
}

({int requestId, HYSendMessageReq request}) _decodeSendRequest(Uint8List frame) {
  final stream = TarsInputStream(frame);
  expect(stream.read(0, 0, true), 3);
  final packet = TarsUniPacket()..decode(stream.readBytes(1, true));
  expect(packet.servantName, 'liveui');
  expect(packet.funcName, 'sendMessage');
  return (requestId: packet.requestId, request: packet.getByClass('tReq', HYSendMessageReq()));
}

/// 让引擎和假通道之间排着的事件都跑完。
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late String cookie;
  late List<_FakeChannel> channels;
  late List<LiveMessage> received;
  late HuyaDanmaku danmaku;

  HuyaDanmaku create({Duration sendTimeout = const Duration(seconds: 5)}) {
    final engine = HuyaDanmaku(
      superChatFetcher: (_) async => <LiveSuperChatMessage>[],
      cookieProvider: () => cookie,
      sendTimeout: sendTimeout,
      connector:
          (
            String endpoint, {
            Duration? connectTimeout,
            Iterable<String>? protocols,
            Map<String, dynamic>? headers,
            io.HttpClient? customClient,
          }) {
            final channel = _FakeChannel(endpoint);
            channels.add(channel);
            return channel;
          },
    );
    engine.onMessage = received.add;
    return engine;
  }

  Future<void> enterRoom() => danmaku.start(HuyaDanmakuArgs(uid: _presenterUid, topSid: _topSid, subSid: _subSid));

  setUp(() {
    cookie = _loggedInCookie;
    channels = <_FakeChannel>[];
    received = <LiveMessage>[];
    danmaku = create();
  });

  tearDown(() async {
    await danmaku.stop();
  });

  test('未登录：连接地址不带身份，不能发送', () async {
    cookie = '';
    await enterRoom();

    expect(channels.single.endpoint, 'wss://wsapi.huya.com');
    expect(danmaku.sendBlock, LiveDanmakuSendBlock.loginRequired);
    await expectLater(danmaku.sendMessage('你好'), throwsA(isA<LiveDanmakuSendException>()));
    expect(channels.single.sendRequests, isEmpty);
  });

  test('已登录：握手地址带观众身份，发送请求带账号、主播和频道', () async {
    await enterRoom();
    expect(channels.single.endpoint, startsWith('wss://wsapi.huya.com?baseinfo='));
    expect(danmaku.sendBlock, isNull);

    final sending = danmaku.sendMessage('  主播好  ');
    await _settle();
    final sent = _decodeSendRequest(channels.single.sendRequests.single);
    expect(sent.request.tUserId.lUid, _viewerUid);
    expect(sent.request.tUserId.sGuid, '0123456789abcdef0123456789abcdef');
    expect(sent.request.tUserId.sCookie, _loggedInCookie);
    expect(sent.request.lPid, _presenterUid);
    expect(sent.request.lTid, _topSid);
    expect(sent.request.lSid, _subSid);
    expect(sent.request.sContent, '主播好');

    channels.single.incoming.add(_sendReply(requestId: sent.requestId));
    await sending;
  });

  test('登录态无效（返回 905）：发送失败，提示重新登录', () async {
    await enterRoom();
    final sending = danmaku.sendMessage('登录过期了');
    await _settle();
    final sent = _decodeSendRequest(channels.single.sendRequests.single);
    final rejected = expectLater(
      sending,
      throwsA(isA<LiveDanmakuSendException>().having((e) => e.message, 'message', contains('重新登录'))),
    );
    channels.single.incoming.add(_sendReply(requestId: sent.requestId, returned: 905));
    await rejected;
  });

  test('其它错误码：发送失败，带上错误码', () async {
    await enterRoom();
    final sending = danmaku.sendMessage('被拒绝的内容');
    await _settle();
    final sent = _decodeSendRequest(channels.single.sendRequests.single);
    final rejected = expectLater(
      sending,
      throwsA(isA<LiveDanmakuSendException>().having((e) => e.message, 'message', contains('1234'))),
    );
    channels.single.incoming.add(_sendReply(requestId: sent.requestId, returned: 1234));
    await rejected;
  });

  test('服务端没有回应：到时按已发出处理', () async {
    danmaku = create(sendTimeout: const Duration(milliseconds: 40));
    await enterRoom();
    await danmaku.sendMessage('没人理我');
    expect(channels.single.sendRequests, hasLength(1));
  });

  test('同时发两条：请求号不同，回应各归各的', () async {
    await enterRoom();
    final first = danmaku.sendMessage('第一条');
    final second = danmaku.sendMessage('第二条');
    await _settle();
    final requests = channels.single.sendRequests.map(_decodeSendRequest).toList();
    expect(requests.map((r) => r.requestId).toSet(), hasLength(2));

    final secondId = requests.firstWhere((r) => r.request.sContent == '第二条').requestId;
    final firstId = requests.firstWhere((r) => r.request.sContent == '第一条').requestId;
    final secondRejected = expectLater(second, throwsA(isA<LiveDanmakuSendException>()));
    channels.single.incoming.add(_sendReply(requestId: secondId, returned: 1234));
    channels.single.incoming.add(_sendReply(requestId: firstId));

    await first;
    await secondRejected;
  });

  test('服务端把自己刚发的那条推回来：只丢掉这一条', () async {
    await enterRoom();
    final sending = danmaku.sendMessage('我发的');
    await _settle();
    final sent = _decodeSendRequest(channels.single.sendRequests.single);
    channels.single.incoming.add(_sendReply(requestId: sent.requestId));
    await sending;

    channels.single.incoming.add(_chatPush(senderUid: _viewerUid, content: '我发的'));
    channels.single.incoming.add(_chatPush(senderUid: 999, content: '我发的'));
    channels.single.incoming.add(_chatPush(senderUid: _viewerUid, content: '我在网页上发的'));
    channels.single.incoming.add(_chatPush(senderUid: _viewerUid, content: '我发的'));
    await _settle();

    expect(received.map((m) => '${m.userId}:${m.message}'), <String>[
      '999:我发的',
      '$_viewerUid:我在网页上发的',
      '$_viewerUid:我发的',
    ]);
  });

  test('没等到回包但自己那条被推回来了：视为已送达，不用等到超时', () async {
    danmaku = create(sendTimeout: const Duration(minutes: 1));
    await enterRoom();
    final sending = danmaku.sendMessage('回显确认');
    await _settle();
    channels.single.incoming.add(_chatPush(senderUid: _viewerUid, content: '回显确认'));

    await sending.timeout(const Duration(seconds: 2));
    expect(received, isEmpty, reason: '推回来的这条由本机上屏，不重复显示');
  });

  test('发送被拒时不记这条：之后同样内容的推送照常显示', () async {
    await enterRoom();
    final sending = danmaku.sendMessage('被拒的');
    await _settle();
    final sent = _decodeSendRequest(channels.single.sendRequests.single);
    final rejected = expectLater(sending, throwsA(isA<LiveDanmakuSendException>()));
    channels.single.incoming.add(_sendReply(requestId: sent.requestId, returned: 1234));
    await rejected;

    channels.single.incoming.add(_chatPush(senderUid: _viewerUid, content: '被拒的'));
    await _settle();
    expect(received.single.message, '被拒的');
  });

  test('进房后才登录：先用当前账号重连，再发送', () async {
    cookie = '';
    await enterRoom();
    expect(channels.single.endpoint, 'wss://wsapi.huya.com');

    cookie = _loggedInCookie;
    final sending = danmaku.sendMessage('刚登录');
    await _settle();

    expect(channels, hasLength(2));
    expect(channels.first.sendRequests, isEmpty);
    expect(channels.last.endpoint, startsWith('wss://wsapi.huya.com?baseinfo='));
    final sent = _decodeSendRequest(channels.last.sendRequests.single);
    expect(sent.request.tUserId.lUid, _viewerUid);
    channels.last.incoming.add(_sendReply(requestId: sent.requestId));
    await sending;
  });

  test('等回应时连接关闭：发送失败，不会一直挂着', () async {
    await enterRoom();
    final sending = danmaku.sendMessage('发到一半');
    final failed = expectLater(sending, throwsA(isA<LiveDanmakuSendException>()));
    await _settle();
    await danmaku.stop();
    await failed;
  });

  test('还没进房就发送：提示通道未就绪', () async {
    await expectLater(danmaku.sendMessage('太早了'), throwsA(isA<LiveDanmakuSendException>()));
    expect(channels, isEmpty);
  });
}
