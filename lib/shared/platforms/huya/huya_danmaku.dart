import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pure_live/core/logging/core_log.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/shared/platforms/huya/huya_send_message.dart';
import 'package:pure_live/shared/platforms/live_danmaku_sender.dart';
import 'package:pure_live/shared/platforms/huya/huya_utils.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/core/tars/codec/tars_struct.dart';
import 'package:pure_live/core/network/web_socket_util.dart';
import 'package:pure_live/shared/platforms/live_danmaku.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';
import 'package:pure_live/core/tars/game_event_message_board_panel.dart';

// ignore_for_file: no_leading_underscores_for_local_identifiers

class HuyaDanmakuArgs {
  final int uid;
  final int topSid;
  final int subSid;
  HuyaDanmakuArgs({required this.uid, required this.topSid, required this.subSid});
  @override
  String toString() {
    return json.encode({"uid": uid, "topSid": topSid, "subSid": subSid});
  }
}

typedef HuyaSuperChatFetcher = Future<List<LiveSuperChatMessage>> Function(int lPid);

class HuyaDanmaku implements LiveDanmaku, LiveDanmakuSender {
  HuyaDanmaku({
    HuyaSuperChatFetcher? superChatFetcher,
    List<Duration>? superChatRetryDelays,
    String Function()? cookieProvider,
    this._connector,
    this.sendTimeout = const Duration(seconds: 5),
  }) : _superChatFetcher = superChatFetcher ?? ((lPid) => getHuyaSuperChatMessageList(lPid: lPid, first: true)),
       _superChatRetryDelays = List<Duration>.unmodifiable(superChatRetryDelays ?? defaultSuperChatRetryDelays),
       _cookieProvider = cookieProvider ?? (() => CookieSettingsController.to.huyaCookie.value);

  static const List<Duration> defaultSuperChatRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 600),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 4000),
  ];

  final HuyaSuperChatFetcher _superChatFetcher;
  final List<Duration> _superChatRetryDelays;
  final Set<LiveSuperChatMessage> _emittedSuperChats = <LiveSuperChatMessage>{};
  static const int _maxRememberedSuperChats = 512;
  Future<void>? _superChatRefreshFuture;
  bool _superChatRefreshQueued = false;

  @override
  int heartbeatTime = 60 * 1000;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  void markConnected() {
    _connected = true;
  }

  @override
  void markDisconnected() {
    _connected = false;
  }

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onReconnect;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;
  String serverUrl = "wss://wsapi.huya.com";

  WebScoketUtils? webScoketUtils;

  /// Current website heartbeat: `EWSCmdC2S_HeartBeatReq` (20).
  List<int> get heartbeatData {
    final command = TarsOutputStream();
    command.write(20, 0);
    command.write(Uint8List(0), 1);
    return command.toUint8List();
  }

  late HuyaDanmakuArgs danmakuArgs;
  int _generation = 0;

  final String Function() _cookieProvider;
  final WebSocketConnector? _connector;

  /// 等待服务端回应一条 `sendMessage` 的最长时间。
  final Duration sendTimeout;

  /// cookie 不带 `guid` 时用的设备号；同一个引擎实例内保持不变，这样连接地址和
  /// 之后每条发送请求报的是同一个设备。
  late final String _fallbackGuid = _randomHex(16);

  /// 当前这条连接握手时报的观众 uid，匿名连接为 0。
  int _sessionViewerUid = 0;

  /// 已发出、还在等服务端回应的弹幕，按请求号索引。
  final Map<int, Completer<void>> _pendingSends = <int, Completer<void>>{};
  int _lastRequestId = 0;

  /// 自己刚发出的弹幕。本机在发送成功后自己上屏，服务端再把它推回来时据此丢掉，
  /// 避免同一条出现两次。
  final List<({String content, DateTime sentAt, int requestId})> _ownMessages =
      <({String content, DateTime sentAt, int requestId})>[];
  static const Duration _ownMessageEchoWindow = Duration(seconds: 30);

  @override
  Future start(dynamic args) async {
    final generation = ++_generation;
    _superChatRefreshFuture = null;
    _emittedSuperChats.clear();
    _superChatRefreshQueued = false;
    await webScoketUtils?.close();
    webScoketUtils = null;
    if (generation != _generation) return;
    danmakuArgs = args as HuyaDanmakuArgs;
    markDisconnected();
    _failPendingSends('弹幕连接已重置，请重新发送');
    // 登录后把观众身份放进握手地址（网页 H5 客户端的做法），发弹幕要用这条连接；
    // 未登录时地址不变。
    final viewer = _viewerCredentials();
    _sessionViewerUid = viewer?.uid ?? 0;
    webScoketUtils = WebScoketUtils(
      url: viewer == null ? serverUrl : huyaAuthenticatedDanmakuUrl(serverUrl, viewer),
      connector: _connector,
      heartBeatTime: heartbeatTime,
      onMessage: (e) {
        if (generation == _generation) decodeMessage(e);
      },
      onReady: () {
        if (generation != _generation) return;
        markConnected();
        onReady?.call();
        joinRoom();
        // Keep the new room-group connection alive immediately.
        heartbeat();
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        if (generation != _generation) return;
        markDisconnected();
        _failPendingSends('弹幕连接已断开，请稍后重试');
        onReconnect?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        if (generation != _generation) return;
        markDisconnected();
        _failPendingSends('弹幕连接已断开，请稍后重试');
        onClose?.call("服务器连接失败$e");
      },
    );
    await webScoketUtils?.connect();
  }

  void joinRoom() {
    var joinData = getJoinData(danmakuArgs.uid);
    webScoketUtils?.sendMessage(joinData);
  }

  List<int> getJoinData(int uid) {
    try {
      final group = TarsOutputStream();
      group.write(<String>['live:$uid', 'chat:$uid'], 0);
      group.write('', 1);

      final command = TarsOutputStream();
      command.write(16, 0); // EWSCmdC2S_RegisterGroupReq
      command.write(group.toUint8List(), 1);
      return command.toUint8List();
    } catch (e) {
      CoreLog.error(e);
      return [];
    }
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage(heartbeatData);
  }

  @override
  Future stop() async {
    _generation++;
    _superChatRefreshFuture = null;
    _superChatRefreshQueued = false;
    _emittedSuperChats.clear();
    markDisconnected();
    _failPendingSends('弹幕连接已关闭');
    _ownMessages.clear();
    onMessage = null;
    onReconnect = null;
    onClose = null;
    onReady = null;
    await webScoketUtils?.close();
    webScoketUtils = null;
  }

  HuyaViewerCredentials? _viewerCredentials() =>
      HuyaViewerCredentials.fromCookie(_cookieProvider(), fallbackGuid: _fallbackGuid);

  @override
  LiveDanmakuSendBlock? get sendBlock => _viewerCredentials() == null ? LiveDanmakuSendBlock.loginRequired : null;

  @override
  int get maxSendLength => 20;

  @override
  Future<void> sendMessage(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    final viewer = _viewerCredentials();
    if (viewer == null) throw const LiveDanmakuSendException('未登录虎牙账号');
    if (webScoketUtils == null) throw const LiveDanmakuSendException('弹幕通道未就绪，请稍后再试');
    if (_sessionViewerUid != viewer.uid) {
      // 进房后才登录或换了账号：这条连接握手时报的还是原来的身份，换成当前账号重连。
      await start(danmakuArgs);
    }
    final socket = webScoketUtils;
    if (!_connected || socket == null) throw const LiveDanmakuSendException('弹幕通道未就绪，请稍后再试');

    final requestId = _nextRequestId();
    final trace = _randomHex(8);
    final completer = Completer<void>();
    _pendingSends[requestId] = completer;
    _rememberOwnMessage(content, requestId);
    try {
      socket.sendMessage(
        buildHuyaSendMessageCommand(
          viewer: viewer,
          presenterUid: danmakuArgs.uid != 0 ? danmakuArgs.uid : danmakuArgs.topSid,
          topSid: danmakuArgs.topSid,
          subSid: danmakuArgs.subSid,
          content: content,
          requestId: requestId,
          traceId: '$trace:$trace:0:0',
        ),
      );
      await completer.future.timeout(sendTimeout);
    } on TimeoutException {
      // 虎牙不一定对每条 sendMessage 都回包：只有明确的错误码才算失败，没等到回应
      // 按已发出处理，否则正常发送也会被误报成失败。
    } on LiveDanmakuSendException {
      _ownMessages.removeWhere((entry) => entry.requestId == requestId);
      rethrow;
    } finally {
      _pendingSends.remove(requestId);
    }
  }

  int _nextRequestId() {
    // 以毫秒时间起步，同一毫秒内连发也保证递增，不会在 _pendingSends 里撞号。
    final now = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    _lastRequestId = now > _lastRequestId ? now : (_lastRequestId + 1) & 0x7fffffff;
    return _lastRequestId;
  }

  void _completeSend(HuyaWupReply reply) {
    final completer = _pendingSends.remove(reply.requestId);
    if (completer == null || completer.isCompleted) return;
    if (reply.code == 0) {
      completer.complete();
      return;
    }
    completer.completeError(
      LiveDanmakuSendException(
        reply.code == huyaSendMessageInvalidSession
            ? '发送失败：登录状态无效，请重新登录虎牙（错误码 ${reply.code}）'
            : '发送失败（虎牙错误码 ${reply.code}）',
      ),
    );
  }

  void _failPendingSends(String message) {
    if (_pendingSends.isEmpty) return;
    final pending = _pendingSends.values.toList(growable: false);
    _pendingSends.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(LiveDanmakuSendException(message));
    }
  }

  void _rememberOwnMessage(String content, int requestId) {
    final now = DateTime.now();
    _ownMessages.removeWhere((entry) => now.difference(entry.sentAt) > _ownMessageEchoWindow);
    _ownMessages.add((content: content, sentAt: now, requestId: requestId));
  }

  /// 服务端把观众自己刚发的那条推回来了：这一条由本机上屏，推送不再显示。
  /// 只按"发送者是自己且内容对得上"消掉一次，同账号在别处发的弹幕照常显示。
  /// 被推回来说明已经送达，还在等回包的那次发送就此完成。
  bool _isEchoOfOwnMessage(HYMessage message) {
    if (_sessionViewerUid == 0 || message.userInfo.uid != _sessionViewerUid) return false;
    final now = DateTime.now();
    final content = message.content.trim();
    final index = _ownMessages.indexWhere(
      (entry) => entry.content == content && now.difference(entry.sentAt) <= _ownMessageEchoWindow,
    );
    if (index < 0) return false;
    final delivered = _pendingSends.remove(_ownMessages.removeAt(index).requestId);
    if (delivered != null && !delivered.isCompleted) delivered.complete();
    return true;
  }

  static String _randomHex(int byteCount) {
    final random = Random.secure();
    return List<String>.generate(byteCount, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> decodeMessage(List<int> data) async {
    try {
      var stream = TarsInputStream(Uint8List.fromList(data));
      var type = stream.read(0, 0, false);
      if (type == 7) {
        stream = TarsInputStream(stream.readBytes(1, false));
        HYPushMessage wSPushMessage = HYPushMessage();
        wSPushMessage.readFrom(stream);
        await _decodePush(wSPushMessage.uri, wSPushMessage.msg);
      } else if (type == 22) {
        final push = HYPushMessageV2();
        push.readFrom(TarsInputStream(stream.readBytes(1, false)));
        for (final item in push.items) {
          await _decodePush(item.uri, item.msg, messageId: item.messageId);
        }
      } else if (type == 4) {
        // EWSCmd_WupRsp：这条连接发出的请求（sendMessage）的回应。
        _completeSend(parseHuyaWupReply(stream.readBytes(1, false)));
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  Future<void> _decodePush(int uri, List<int> payload, {int messageId = 0}) async {
    if (uri == 1400) {
      final messageNotice = HYMessage();
      messageNotice.readFrom(TarsInputStream(Uint8List.fromList(payload)));
      if (_isEchoOfOwnMessage(messageNotice)) return;
      final color = messageNotice.bulletFormat.fontColor;
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.chat,
          color: color <= 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
          message: messageNotice.content,
          userName: messageNotice.userInfo.nickName,
          userId: messageNotice.userInfo.uid.toString(),
          messageId: messageId > 0 ? 'huya:$messageId' : '',
        ),
      );
    } else if (uri == 8006) {
      final attendeeCount = TarsInputStream(Uint8List.fromList(payload)).read(0, 0, false);
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.online,
          // Current website captures keep iAttendeeCount in the same
          // multi-million popularity range as the list value.
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.popularity, value: attendeeCount),
          color: LiveMessageColor.white,
          message: '',
          userName: '',
          messageId: messageId > 0 ? 'huya:$messageId' : '',
        ),
      );
    } else if (uri == 2001314) {
      // 头条通知（`uri 2001314`）的消息体**可能**就是留言板面板（上游 C-9）：是面板就
      // 直接用它的条目（每条留言立刻上报，空面板表示留言板已空、不必再请求），不是
      // 面板才照旧后台补拉。
      final fromPanel = HuyaDanmaku.superChatsFromPanel(payload);
      if (fromPanel != null) {
        for (final chat in fromPanel) {
          if (!_rememberSuperChat(chat)) continue;
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.superChat,
              userName: 'SUPER_CHAT_MESSAGE',
              message: 'SUPER_CHAT_MESSAGE',
              color: LiveMessageColor.white,
              data: chat,
            ),
          );
        }
        return;
      }
      // The notification can arrive before the message-board WUP result is
      // updated. Fetching once here loses that SC until a manual room refresh;
      // awaiting the HTTP call also serializes unrelated websocket messages.
      // Reconcile in the background with a small bounded retry window instead.
      _scheduleSuperChatRefresh(_generation);
    } else if (uri == 8001) {
      // `EndLiveNotice`：主播结束直播（Tars 字段 0 是 lPresenterUid，0 表示没点名）。
      // 服务器不会关掉这条 socket，3.x 也忽略了它，于是房间一直停在"直播中"
      // （上游 C-10）。这里照虎牙网页客户端的行为结束这一路弹幕。
      var presenterUid = 0;
      try {
        final raw = TarsInputStream(Uint8List.fromList(payload)).read(0, 0, false);
        presenterUid = raw is int ? raw : 0;
      } catch (_) {
        // 不是结束通知：当作没收到。
        return;
      }
      final mine = danmakuArgs.uid;
      if (presenterUid == 0 || presenterUid == mine) {
        onClose?.call("直播已结束");
        await stop();
      }
    }
  }

  /// `uri 2001314` 的消息体当留言板面板解（上游 C-9）：是面板就返回它的条目
  /// （**空列表表示留言板已空**，调用方不必再请求），不是面板返回 null（调用方照旧
  /// 后台补拉）。字段映射与 WUP 补拉共用 `huyaSuperChatsFromPanel`。
  @visibleForTesting
  static List<LiveSuperChatMessage>? superChatsFromPanel(List<int> payload, {DateTime? now}) {
    if (payload.isEmpty) return null;
    final GameEventMessageBoardPanel panel;
    try {
      final bytes = Uint8List.fromList(payload);
      // 不是面板（连 tag 1 的列表都没有）时不能当成"留言板已空"，那样会丢掉醒目留言。
      if (!TarsInputStream(bytes).skipToTag(1)) return null;
      panel = GameEventMessageBoardPanel()..readFrom(TarsInputStream(bytes));
    } catch (_) {
      return null;
    }
    return huyaSuperChatsFromPanel(panel, now: now);
  }

  void _scheduleSuperChatRefresh(int generation) {
    if (generation != _generation) return;
    if (_superChatRefreshFuture != null) {
      _superChatRefreshQueued = true;
      return;
    }

    _superChatRefreshQueued = false;
    final future = _refreshSuperChats(generation);
    _superChatRefreshFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_superChatRefreshFuture, future)) {
          _superChatRefreshFuture = null;
        }
        if (_superChatRefreshQueued && generation == _generation) {
          _scheduleSuperChatRefresh(generation);
        }
      }),
    );
  }

  Future<void> _refreshSuperChats(int generation) async {
    for (var attempt = 0; attempt < _superChatRetryDelays.length; attempt++) {
      final delay = _superChatRetryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (generation != _generation || danmakuArgs.topSid == 0) return;

      try {
        final messages = await _superChatFetcher(danmakuArgs.topSid).timeout(const Duration(seconds: 3));
        if (generation != _generation) return;

        final hadKnownMessages = _emittedSuperChats.isNotEmpty;
        var emittedNewMessage = false;
        for (final message in messages) {
          if (!_rememberSuperChat(message)) continue;
          emittedNewMessage = true;
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.superChat,
              userName: 'SUPER_CHAT_MESSAGE',
              message: 'SUPER_CHAT_MESSAGE',
              color: LiveMessageColor.white,
              data: message,
            ),
          );
        }

        // Once this transport already has a baseline, an unseen item proves
        // that the delayed WUP board caught up and no later retry is needed.
        if (hadKnownMessages && emittedNewMessage) return;
      } catch (error) {
        if (generation == _generation && attempt == _superChatRetryDelays.length - 1) {
          CoreLog.error('huya_super_chat_refresh_failed: $error');
        }
      }
    }
  }

  bool _rememberSuperChat(LiveSuperChatMessage message) {
    if (!_emittedSuperChats.add(message)) return false;
    while (_emittedSuperChats.length > _maxRememberedSuperChats) {
      _emittedSuperChats.remove(_emittedSuperChats.first);
    }
    return true;
  }

  @visibleForTesting
  Future<void> waitForPendingSuperChatRefresh() async {
    while (_superChatRefreshFuture != null) {
      await _superChatRefreshFuture;
    }
  }
}

class HYPushMessage extends TarsStruct {
  int pushType = 0;
  int uri = 0;
  List<int> msg = <int>[];
  int protocolType = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    pushType = inputStream.read(pushType, 0, false);
    uri = inputStream.read(uri, 1, false);
    msg = inputStream.readBytes(2, false);
    protocolType = inputStream.read(protocolType, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYPushMessage()
      ..pushType = pushType
      ..uri = uri
      ..msg = List<int>.from(msg)
      ..protocolType = protocolType;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYPushMessageV2 extends TarsStruct {
  String groupId = '';
  List<HYMessageItem> items = <HYMessageItem>[];

  @override
  void readFrom(TarsInputStream inputStream) {
    groupId = inputStream.read(groupId, 0, false);
    items = inputStream.readList<HYMessageItem>(<HYMessageItem>[HYMessageItem()], 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(groupId, 0);
    outputStream.write(items, 1);
  }

  @override
  Object deepCopy() => HYPushMessageV2()
    ..groupId = groupId
    ..items = items.map((item) => item.deepCopy() as HYMessageItem).toList();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYMessageItem extends TarsStruct {
  int uri = 0;
  List<int> msg = <int>[];
  int messageId = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    uri = inputStream.read(uri, 0, false);
    msg = inputStream.readBytes(1, false);
    messageId = inputStream.read(messageId, 2, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(uri, 0);
    outputStream.write(Uint8List.fromList(msg), 1);
    outputStream.write(messageId, 2);
  }

  @override
  Object deepCopy() => HYMessageItem()
    ..uri = uri
    ..msg = List<int>.from(msg)
    ..messageId = messageId;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYSender extends TarsStruct {
  int uid = 0;
  int lMid = 0;
  String nickName = "";
  int gender = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    uid = inputStream.read(uid, 0, false);
    lMid = inputStream.read(lMid, 0, false);
    nickName = inputStream.read(nickName, 2, false);
    gender = inputStream.read(gender, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYSender()
      ..uid = uid
      ..lMid = lMid
      ..nickName = nickName
      ..gender = gender;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYMessage extends TarsStruct {
  HYSender userInfo = HYSender();
  String content = "";
  HYBulletFormat bulletFormat = HYBulletFormat();

  @override
  void readFrom(TarsInputStream inputStream) {
    userInfo = inputStream.readTarsStruct(userInfo, 0, false) as HYSender;
    content = inputStream.read(content, 3, false);
    bulletFormat = inputStream.readTarsStruct(bulletFormat, 6, false) as HYBulletFormat;
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYMessage()
      ..userInfo = userInfo.deepCopy() as HYSender
      ..content = content
      ..bulletFormat = bulletFormat.deepCopy() as HYBulletFormat;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYBulletFormat extends TarsStruct {
  int fontColor = 0;
  int fontSize = 4;
  int textSpeed = 0;
  int transitionType = 1;

  @override
  void readFrom(TarsInputStream inputStream) {
    fontColor = inputStream.read(fontColor, 0, false);
    fontSize = inputStream.read(fontSize, 1, false);
    textSpeed = inputStream.read(textSpeed, 2, false);
    transitionType = inputStream.read(transitionType, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYBulletFormat()
      ..fontColor = fontColor
      ..fontSize = fontSize
      ..textSpeed = textSpeed
      ..transitionType = transitionType;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}
