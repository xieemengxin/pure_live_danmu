import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';
import 'package:pure_live/core/tars/tup/tars_uni_packet.dart';
import 'package:pure_live/shared/platforms/huya/huya_send_message.dart';

// 基准输入与基准字节：用 simple_live_reborn 的 tars_dart 编码器，按它
// `HuyaDanmaku.sendDanmaku` / `_buildWsUrl` 的写法对同一组输入生成。虎牙线上接受的
// 就是那份实现发出的字节，所以这里要求逐字节一致。
const int _uid = 1234567890123;
const String _guid = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const int _topSid = 1199512345678;
const String _content = '主播好厉害 666';
const int _requestId = 1234567;
const String _traceId = 'abcdef0123456789:abcdef0123456789:0:0';
const String _referenceCommandSha256 = 'b394571033904b7d8896c740ee69045e3437f656325eb8ec2d91caf8c5479837';
const int _referenceCommandLength = 726;
const String _referenceWsUrl =
    'wss://wsapi.huya.com?baseinfo=AwAAAR9x%2BwTLFiBhMWIyYzNkNGU1ZjYwNzE4MjkzYTRiNWM2ZDdlOGY5MCYad2ViaDUmMjYwNDI4'
    'MTY0NiZ3ZWJzb2NrZXQ2DEhVWUEmWkgmMjA1MkYAVgBsdgCGAJYAqAACBghIVVlBX05FVBYBMAYLSFVZQV9WU0RLVUEWGndlYmg1JjI2MDQy'
    'ODE2NDYmd2Vic29ja2V0';

// 超过 255 字节，覆盖长字符串（STRING4）编码。
final String _cookie = 'yyuid=$_uid; guid=$_guid; udb_passdata=3; udb_biztoken=${'x' * 300}';

HuyaViewerCredentials _viewer() => HuyaViewerCredentials.fromCookie(_cookie, fallbackGuid: 'unused')!;

Uint8List _command({int subSid = 0}) => buildHuyaSendMessageCommand(
  viewer: _viewer(),
  presenterUid: _topSid,
  topSid: _topSid,
  subSid: subSid,
  content: _content,
  requestId: _requestId,
  traceId: _traceId,
);

void main() {
  group('观众身份', () {
    test('从 cookie 取 yyuid 和 guid', () {
      final viewer = _viewer();
      expect(viewer.uid, _uid);
      expect(viewer.guid, _guid);
      expect(viewer.cookie, _cookie);
    });

    test('没有 yyuid 时用 udb_uid；cookie 不带 guid 时用备用值', () {
      final viewer = HuyaViewerCredentials.fromCookie('foo=1; udb_uid=42', fallbackGuid: 'fallback')!;
      expect(viewer.uid, 42);
      expect(viewer.guid, 'fallback');
    });

    test('cookie 里没有账号 uid 就是未登录', () {
      expect(HuyaViewerCredentials.fromCookie('', fallbackGuid: 'g'), isNull);
      expect(HuyaViewerCredentials.fromCookie('guid=abc; yyuid=0', fallbackGuid: 'g'), isNull);
      expect(HuyaViewerCredentials.fromCookie('myyyuid=7', fallbackGuid: 'g'), isNull);
    });
  });

  group('sendMessage 请求帧', () {
    test('与参考实现逐字节一致', () {
      final command = _command();
      expect(command.length, _referenceCommandLength);
      expect(sha256.convert(command).toString(), _referenceCommandSha256);
    });

    test('外层是 WupReq（3），带请求号、追踪号和 WUP 包的 md5', () {
      final stream = TarsInputStream(_command());
      expect(stream.read(0, 0, true), 3);
      final wup = stream.readBytes(1, true);
      expect(stream.read(0, 2, true), _requestId);
      expect(stream.read('', 3, true), _traceId);
      expect(stream.read('', 6, true), md5.convert(wup).toString());
    });

    test('WUP 包调用 liveui.sendMessage，请求体带观众身份、频道和内容', () {
      final wup = TarsInputStream(_command()).readBytes(1, true);
      final packet = TarsUniPacket()..decode(wup);
      expect(packet.servantName, 'liveui');
      expect(packet.funcName, 'sendMessage');
      expect(packet.requestId, _requestId);

      final request = packet.getByClass('tReq', HYSendMessageReq());
      expect(request.tUserId.lUid, _uid);
      expect(request.tUserId.sGuid, _guid);
      expect(request.tUserId.sHuYaUA, huyaWebDanmakuUserAgent);
      expect(request.tUserId.sCookie, _cookie);
      expect(request.lTid, _topSid);
      expect(request.lSid, _topSid, reason: '子频道为 0 时用顶级频道');
      expect(request.lPid, _topSid);
      expect(request.sContent, _content);
    });

    test('有子频道时 lSid 用子频道', () {
      final wup = TarsInputStream(_command(subSid: 987654321)).readBytes(1, true);
      final request = (TarsUniPacket()..decode(wup)).getByClass('tReq', HYSendMessageReq());
      expect(request.lTid, _topSid);
      expect(request.lSid, 987654321);
    });
  });

  test('带登录身份的连接地址与参考实现一致', () {
    expect(huyaAuthenticatedDanmakuUrl('wss://wsapi.huya.com', _viewer()), _referenceWsUrl);
  });

  group('sendMessage 回应', () {
    // 函数返回值在空键下，UniAttribute.put 不接受空键，这里直接写进数据表。
    Uint8List reply({required int requestId, Map<String, String> status = const {}, int? returned}) {
      final packet = TarsUniPacket()
        ..setTarsVersion(3)
        ..requestId = requestId
        ..servantName = 'liveui'
        ..funcName = 'sendMessage'
        ..setTarsStatus(status)
        ..put('tRsp', 0);
      if (returned != null) packet.newData[''] = (TarsOutputStream()..write(returned, 0)).toUint8List();
      return packet.encode();
    }

    test('返回值为 0 就是成功', () {
      final parsed = parseHuyaWupReply(reply(requestId: 77, returned: 0));
      expect(parsed.requestId, 77);
      expect(parsed.code, 0);
    });

    test('没有返回值、状态里也没有错误码，按成功处理', () {
      expect(parseHuyaWupReply(reply(requestId: 77)).code, 0);
    });

    test('线上对无效登录态的回应：状态码缺省，返回值 905', () {
      final wup = reply(
        requestId: 78,
        status: {'STATUS_RESULT_DESC': 'wup request biz execption:905'},
        returned: huyaSendMessageInvalidSession,
      );
      // 线上实测这份返回值的字节是 01 03 89。
      expect((TarsUniPacket()..decode(wup)).newData[''], <int>[0x01, 0x03, 0x89]);

      final parsed = parseHuyaWupReply(wup);
      expect(parsed.requestId, 78);
      expect(parsed.code, 905);
    });

    test('tars 调用本身失败时用状态里的结果码', () {
      expect(parseHuyaWupReply(reply(requestId: 79, status: {'STATUS_RESULT_CODE': '-2'})).code, -2);
    });

    test('不是 WUP 包就抛错，由调用方忽略这一帧', () {
      expect(() => parseHuyaWupReply(Uint8List.fromList([1, 2])), throwsA(anything));
      final junk = TarsOutputStream()..write('not a packet', 0);
      expect(() => parseHuyaWupReply(base64Decode(base64Encode(junk.toUint8List()))), throwsA(anything));
    });
  });
}
