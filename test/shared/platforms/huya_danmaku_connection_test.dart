import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';
import 'package:pure_live/core/tars/codec/tars_struct.dart';
import 'package:pure_live/shared/platforms/huya/huya_danmaku.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const int _presenterUid = 5550001;

/// 代替真实 WebSocket。[healthy] 为真时像虎牙服务器一样回进房（17）和心跳（21）；
/// 为假时握手成功后什么都不回，模拟手机切网/挂起后残留的"半开"连接。
class _FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _FakeChannel({required this.healthy, this.handshakeError});

  final bool healthy;
  final Object? handshakeError;
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<int> sentCommands = <int>[];
  bool closed = false;
  late final _FakeSink _sink = _FakeSink(this);

  void push(Uint8List frame) {
    if (!incoming.isClosed) incoming.add(frame);
  }

  void _onSent(List<int> data) {
    final command = TarsInputStream(Uint8List.fromList(data)).read(0, 0, false) as int;
    sentCommands.add(command);
    if (!healthy) return;
    if (command == 16) push(_command(17));
    if (command == 20) push(_command(21));
  }

  @override
  Future<void> get ready => handshakeError == null ? Future<void>.value() : Future<void>.error(handshakeError!);
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
  void add(dynamic data) => _channel._onSent(data as List<int>);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closed = true;
    if (!_done.isCompleted) _done.complete();
    if (!_channel.incoming.isClosed) await _channel.incoming.close();
  }

  @override
  Future<void> get done => _done.future;
}

Uint8List _command(int type, [List<int> body = const <int>[]]) {
  final frame = TarsOutputStream()
    ..write(type, 0)
    ..write(Uint8List.fromList(body), 1);
  return frame.toUint8List();
}

/// 服务端的旧版推送（外层命令 7）。
Uint8List _push(int uri, List<int> payload) {
  final push = TarsOutputStream()
    ..write(0, 0)
    ..write(uri, 1)
    ..write(Uint8List.fromList(payload), 2);
  return _command(7, push.toUint8List());
}

/// `EndLiveNotice`（uri 8001）：lPresenterUid、iReason、lLiveId、sReason。
Uint8List _endLiveNotice(int presenterUid) {
  final notice = TarsOutputStream()
    ..write(presenterUid, 0)
    ..write(1, 1)
    ..write(7000001, 2)
    ..write('', 3);
  return _push(8001, notice.toUint8List());
}

/// `BeginLiveNotice`（uri 8000）：字段 0 是 lPresenterUid。
Uint8List _beginLiveNotice(int presenterUid) {
  final notice = TarsOutputStream()..write(presenterUid, 0);
  return _push(8000, notice.toUint8List());
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

Uint8List _chat(String content) {
  final message = TarsOutputStream()
    ..write(_Sender(42, '观众'), 0)
    ..write(content, 3);
  return _push(1400, message.toUint8List());
}

void main() {
  late List<_FakeChannel> channels;
  late List<LiveMessage> received;
  late List<String> closes;

  HuyaDanmaku create(_FakeChannel Function(int attempt) channelFor) {
    final engine = HuyaDanmaku(
      superChatFetcher: (_) async => <LiveSuperChatMessage>[],
      cookieProvider: () => '',
      connector:
          (
            String endpoint, {
            Duration? connectTimeout,
            Iterable<String>? protocols,
            Map<String, dynamic>? headers,
            io.HttpClient? customClient,
          }) {
            final channel = channelFor(channels.length);
            channels.add(channel);
            return channel;
          },
    );
    engine.onMessage = received.add;
    engine.onClose = closes.add;
    return engine;
  }

  HuyaDanmakuArgs room() => HuyaDanmakuArgs(uid: _presenterUid, topSid: 1, subSid: 1);

  setUp(() {
    channels = <_FakeChannel>[];
    received = <LiveMessage>[];
    closes = <String>[];
  });

  test('主播下播通知（8001）只提示，不断开弹幕连接：主播恢复推流后的弹幕照常显示', () {
    fakeAsync((async) {
      final danmaku = create((_) => _FakeChannel(healthy: true));
      unawaited(danmaku.start(room()));
      async.flushMicrotasks();
      final channel = channels.single;

      channel.push(_endLiveNotice(_presenterUid));
      async.elapse(const Duration(seconds: 5));
      channel.push(_beginLiveNotice(_presenterUid));
      channel.push(_chat('回来了'));
      async.elapse(const Duration(seconds: 1));

      expect(closes, isEmpty);
      expect(channel.closed, isFalse);
      expect(danmaku.isConnected, isTrue);
      expect(received.where((m) => m.type == LiveMessageType.chat).map((m) => m.message), ['回来了']);
      final notices = received.where((m) => m.type == LiveMessageType.notice).map((m) => m.message).toList();
      expect(notices, hasLength(2));

      unawaited(danmaku.stop());
      async.flushMicrotasks();
    });
  });

  test('直播中虎牙周期性重发的开播通知（8000）不提示；下播后再开播才提示，且各提示一次', () {
    fakeAsync((async) {
      final danmaku = create((_) => _FakeChannel(healthy: true));
      unawaited(danmaku.start(room()));
      async.flushMicrotasks();
      final channel = channels.single;

      // 实测：直播中的房间每 5 分钟左右收到一次同一场次的 8000，一次连着 3 条。
      for (var i = 0; i < 3; i++) {
        channel.push(_beginLiveNotice(_presenterUid));
      }
      async.elapse(const Duration(seconds: 1));
      expect(received.where((m) => m.type == LiveMessageType.notice), isEmpty);

      channel.push(_endLiveNotice(_presenterUid));
      channel.push(_endLiveNotice(_presenterUid));
      channel.push(_beginLiveNotice(_presenterUid));
      channel.push(_beginLiveNotice(_presenterUid));
      async.elapse(const Duration(seconds: 1));

      final notices = received.where((m) => m.type == LiveMessageType.notice).map((m) => m.message).toList();
      expect(notices, hasLength(2));
      expect(notices.first, isNot(notices.last));

      unawaited(danmaku.stop());
      async.flushMicrotasks();
    });
  });

  test('别的主播的下播通知不提示', () {
    fakeAsync((async) {
      final danmaku = create((_) => _FakeChannel(healthy: true));
      unawaited(danmaku.start(room()));
      async.flushMicrotasks();

      channels.single.push(_endLiveNotice(_presenterUid + 1));
      async.elapse(const Duration(seconds: 1));

      expect(received.where((m) => m.type == LiveMessageType.notice), isEmpty);
      unawaited(danmaku.stop());
      async.flushMicrotasks();
    });
  });

  test('断网超过一分钟也不放弃重连：网络恢复后自动连上，不用重进直播间', () {
    fakeAsync((async) {
      // 前 20 次握手都失败（地铁/电梯里没网），之后恢复。
      final danmaku = create(
        (attempt) => attempt < 20
            ? _FakeChannel(healthy: true, handshakeError: const io.SocketException('Network is unreachable'))
            : _FakeChannel(healthy: true),
      );
      unawaited(danmaku.start(room()));
      async.elapse(const Duration(minutes: 5));

      expect(closes, isEmpty);
      expect(channels.length, greaterThanOrEqualTo(21));
      expect(danmaku.isConnected, isTrue);
      expect(channels.last.sentCommands, contains(16), reason: '重连后要重新进房');

      unawaited(danmaku.stop());
      async.flushMicrotasks();
    });
  });

  test('连上后服务端再无任何回包（半开连接）时，100 秒内换新连接', () {
    fakeAsync((async) {
      final danmaku = create((attempt) => _FakeChannel(healthy: attempt > 0));
      unawaited(danmaku.start(room()));
      async.flushMicrotasks();
      expect(channels, hasLength(1));

      async.elapse(const Duration(seconds: 100));

      expect(channels.length, 2);
      expect(channels.first.closed, isTrue);
      expect(danmaku.isConnected, isTrue);
      expect(closes, isEmpty);

      unawaited(danmaku.stop());
      async.flushMicrotasks();
    });
  });

  test('健康连接（虎牙每次心跳都有回应）长时间保持，不会误判断开', () {
    fakeAsync((async) {
      final danmaku = create((_) => _FakeChannel(healthy: true));
      unawaited(danmaku.start(room()));
      async.elapse(const Duration(minutes: 20));

      expect(channels, hasLength(1));
      expect(danmaku.isConnected, isTrue);

      unawaited(danmaku.stop());
      async.flushMicrotasks();
    });
  });
}
