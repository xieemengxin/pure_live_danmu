// Opt-in external probe, deliberately outside the ordinary offline test suite.
// Nothing is persisted. It joins a live Huya room the way a signed-in viewer
// does and posts one chat line:
//
//   PURELIVE_HUYA_ROOM    room id, default 660000
//   PURELIVE_HUYA_COOKIE  the viewer's web cookie; when set, the line is really
//                         posted to that room
//   PURELIVE_HUYA_TEXT    the line to post, default "666"
//
// Without a cookie it signs in with a made-up one that carries no session
// token. Huya must refuse that, which is enough to check that chat still
// arrives on the signed-in connection URL and that a real reply decodes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/shared/platforms/huya/huya_danmaku.dart';
import 'package:pure_live/shared/platforms/live_danmaku_sender.dart';

const String _madeUpCookie = 'yyuid=1; guid=00000000000000000000000000000000';

Future<HuyaDanmakuArgs> _roomArgs(String room) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(
      Uri.https('mp.huya.com', '/cache.php', {'m': 'Live', 'do': 'profileRoom', 'roomid': room}),
    );
    request.headers.set('user-agent', 'Mozilla/5.0');
    final response = await request.close().timeout(const Duration(seconds: 20));
    expect(response.statusCode, 200);
    final data = (jsonDecode(await utf8.decoder.bind(response).join()) as Map)['data'] as Map;
    expect(data['liveStatus'], 'ON', reason: 'the probe needs a room that is live');
    final stream = ((data['stream'] as Map)['baseSteamInfoList'] as List).first as Map;
    return HuyaDanmakuArgs(
      uid: int.parse((data['profileInfo'] as Map)['uid'].toString()),
      topSid: int.parse(stream['lChannelId'].toString()),
      subSid: int.parse(stream['lSubChannelId'].toString()),
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('production Huya accepts or refuses a posted chat line with a decodable reply', () async {
    final room = Platform.environment['PURELIVE_HUYA_ROOM'] ?? '660000';
    final realCookie = Platform.environment['PURELIVE_HUYA_COOKIE']?.trim() ?? '';
    final text = Platform.environment['PURELIVE_HUYA_TEXT'] ?? '666';
    final signedIn = realCookie.isNotEmpty;

    final chat = <LiveMessage>[];
    final firstChat = Completer<void>();
    final danmaku = HuyaDanmaku(
      superChatFetcher: (_) async => <LiveSuperChatMessage>[],
      cookieProvider: () => signedIn ? realCookie : _madeUpCookie,
    );
    danmaku.onMessage = (message) {
      if (message.type != LiveMessageType.chat) return;
      chat.add(message);
      if (!firstChat.isCompleted) firstChat.complete();
    };

    try {
      await danmaku.start(await _roomArgs(room)).timeout(const Duration(seconds: 20));
      expect(danmaku.isConnected, isTrue);
      expect(danmaku.sendBlock, isNull);

      await firstChat.future.timeout(const Duration(seconds: 30));
      // ignore: avoid_print
      print('received ${chat.length} chat line(s) on the signed-in connection URL');

      Object? refusal;
      final watch = Stopwatch()..start();
      try {
        await danmaku.sendMessage(text);
      } on LiveDanmakuSendException catch (error) {
        refusal = error;
      }
      // ignore: avoid_print
      print(
        'send outcome after ${watch.elapsedMilliseconds} ms: ${refusal ?? 'accepted (or no reply before timeout)'}',
      );

      if (signedIn) {
        expect(refusal, isNull, reason: 'a valid session should be allowed to post');
      } else {
        expect(refusal, isNotNull, reason: 'a cookie without a session token must be refused');
      }
    } finally {
      await danmaku.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
