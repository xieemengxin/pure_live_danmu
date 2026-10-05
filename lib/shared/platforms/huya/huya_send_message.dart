import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pure_live/core/tars/types.dart';
import 'package:pure_live/core/tars/codec/tars_struct.dart';
import 'package:pure_live/core/tars/tup/tars_uni_packet.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';

// ignore_for_file: no_leading_underscores_for_local_identifiers

/// 虎牙网页 H5 客户端在弹幕连接和 `sendMessage` 里上报的终端标识。
const String huyaWebDanmakuUserAgent = 'webh5&2604281646&websocket';

/// 发弹幕用的观众身份，全部取自登录后的网页 cookie。
class HuyaViewerCredentials {
  const HuyaViewerCredentials({required this.uid, required this.guid, required this.cookie});

  final int uid;
  final String guid;
  final String cookie;

  /// cookie 里有没有一份登录会话：账号 uid 加会话令牌 `udb_biztoken`（登录成功时由
  /// 登录接口一起写入；匿名访客只有 `udb_anouid` / `udb_anobiztoken`）。
  static bool hasSession(String cookie) =>
      fromCookie(cookie, fallbackGuid: '') != null && RegExp(r'(?:^|;\s*)udb_biztoken=[^;\s]+').hasMatch(cookie);

  /// cookie 里没有账号 uid（`yyuid` / `udb_uid`）时返回 null，即未登录。
  /// cookie 不带 `guid` 时用 [fallbackGuid]。
  static HuyaViewerCredentials? fromCookie(String cookie, {required String fallbackGuid}) {
    final uid = int.tryParse(RegExp(r'(?:^|;\s*)(?:yyuid|udb_uid)=(\d+)').firstMatch(cookie)?.group(1) ?? '');
    if (uid == null || uid <= 0) return null;
    final guid = RegExp(r'(?:^|;\s*)guid=([a-f0-9]+)').firstMatch(cookie)?.group(1);
    return HuyaViewerCredentials(uid: uid, guid: guid == null || guid.isEmpty ? fallbackGuid : guid, cookie: cookie);
  }
}

/// 带登录身份的弹幕连接地址：身份放在 `baseinfo` 查询参数里，握手不带 cookie。
String huyaAuthenticatedDanmakuUrl(String serverUrl, HuyaViewerCredentials viewer) {
  final info = TarsOutputStream();
  info.write(viewer.uid, 0);
  info.write(viewer.guid, 1);
  info.write(huyaWebDanmakuUserAgent, 2);
  info.write('HUYA&ZH&2052', 3);
  info.write('', 4);
  info.write('', 5);
  info.write(0, 6);
  info.write('', 7);
  info.write('', 8);
  info.write('', 9);
  info.write(<String, String>{'HUYA_NET': '0', 'HUYA_VSDKUA': huyaWebDanmakuUserAgent}, 10);
  return '$serverUrl?baseinfo=${Uri.encodeComponent(base64Encode(info.toUint8List()))}';
}

/// 一条 `liveui.sendMessage` 请求的 WebSocket 帧（`EWSCmd_WupReq` = 3）。
///
/// [presenterUid] 是主播 uid，[topSid] / [subSid] 是直播间的频道号；子频道为 0 时
/// 用顶级频道。[traceId] 形如 `<16 位十六进制>:<同一串>:0:0`。
Uint8List buildHuyaSendMessageCommand({
  required HuyaViewerCredentials viewer,
  required int presenterUid,
  required int topSid,
  required int subSid,
  required String content,
  required int requestId,
  required String traceId,
}) {
  final request = HYSendMessageReq()
    ..tUserId = (HuyaUserId()
      ..lUid = viewer.uid
      ..sGuid = viewer.guid
      ..sHuYaUA = huyaWebDanmakuUserAgent
      ..sCookie = viewer.cookie)
    ..lTid = topSid
    ..lSid = subSid == 0 ? topSid : subSid
    ..sContent = content
    ..lPid = presenterUid;

  final packet = TarsUniPacket()
    ..setTarsVersion(3)
    ..requestId = requestId
    ..servantName = 'liveui'
    ..funcName = 'sendMessage'
    ..put('tReq', request);
  final wup = packet.encode();

  final command = TarsOutputStream();
  command.write(3, 0);
  command.write(wup, 1);
  command.write(requestId, 2);
  command.write(traceId, 3);
  command.write(0, 4);
  command.write(0, 5);
  command.write(md5.convert(wup).toString(), 6);
  return command.toUint8List();
}

/// 服务端对一次 WUP 请求的回应（`EWSCmd_WupRsp` = 4）。
class HuyaWupReply {
  const HuyaWupReply({required this.requestId, required this.code, this.status = 0, this.toast = ''});

  final int requestId;

  /// 函数的返回值（tars 调用本身失败时是它的结果码）；0 表示调用成功。
  final int code;

  /// 回应体 `SendMessageRsp.iStatus`；回应里没有回应体时为 0。
  final int status;

  /// 回应体 `SendMessageRsp.sToast`：虎牙给观众看的拒绝原因，没有时为空。
  final String toast;

  /// 这条弹幕没发出去时给观众的说明，发出去了为 null。
  ///
  /// 判定照虎牙网页端：回应体里状态不为 0 且带提示文字就是被拒，提示原样给观众；
  /// 状态不为 0 但没有提示，网页端按成功处理。返回值不为 0 时回应里可能根本没有
  /// 回应体（线上对无效登录态就是这样），同样算被拒。
  String? get sendRefusal {
    if (code == huyaSendMessageUnverifiedAccount || status == huyaSendMessageUnverifiedAccount) {
      return '发送失败：虎牙要求账号绑定手机，或登录状态已失效，请在虎牙确认后重新登录'
          '（错误码 $huyaSendMessageUnverifiedAccount）';
    }
    if (status != 0 && toast.isNotEmpty) return '发送失败：$toast';
    if (code != 0) return '发送失败（虎牙错误码 $code）';
    return null;
  }
}

/// 虎牙不认这个账号发言时的状态。网页端收到它会引导观众绑定手机；用不带会话令牌的
/// cookie 对线上实测，返回值也是它（那时回应里没有回应体）。
const int huyaSendMessageUnverifiedAccount = 905;

/// 解出 `EWSCmd_WupRsp` 帧里的 WUP 包；[wup] 是帧的 tag 1 字节。
///
/// tars 状态里的结果码只说明这次调用有没有送到服务；业务上成没成是函数的返回值
/// （空键下）和回应体 `tRsp` 里的状态。线上成功的回应两样都有；对无效登录态的回应
/// 是状态码缺省（按 0 算）、返回值 905、没有回应体。
HuyaWupReply parseHuyaWupReply(Uint8List wup) {
  final packet = TarsUniPacket()..decode(wup);
  var code = packet.getTarsResultCode();
  final returned = packet.newData[''];
  if (code == 0 && returned != null) {
    final value = TarsInputStream(returned).read(0, 0, false);
    if (value is int) code = value;
  }
  var status = 0;
  var toast = '';
  final body = packet.newData['tRsp'];
  if (body != null) {
    try {
      final rsp = TarsInputStream(body).readTarsStruct(HYSendMessageRsp(), 0, false) as HYSendMessageRsp;
      status = rsp.iStatus;
      toast = rsp.sToast.trim();
    } catch (_) {
      // 回应体不是 SendMessageRsp：只看返回值。
    }
  }
  return HuyaWupReply(requestId: packet.requestId, code: code, status: status, toast: toast);
}

/// `liveui.sendMessage` 的回应体。tag 1 是服务端落地的那条消息（`tNotice`），这里
/// 用不到，不读。
class HYSendMessageRsp extends TarsStruct {
  int iStatus = 0;
  String sToast = '';

  @override
  void writeTo(TarsOutputStream _os) {
    _os.write(iStatus, 0);
    _os.write(sToast, 2);
  }

  @override
  void readFrom(TarsInputStream _is) {
    iStatus = _is.read(iStatus, 0, false);
    sToast = _is.read(sToast, 2, false);
  }

  @override
  Object deepCopy() => HYSendMessageRsp()
    ..iStatus = iStatus
    ..sToast = sToast;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYContentFormat extends TarsStruct {
  int iFontColor = -1;
  int iFontSize = 4;
  int iPopupStyle = 0;
  int iNickNameFontColor = -1;
  int iDarkFontColor = -1;
  int iDarkNickNameFontColor = -1;

  @override
  void writeTo(TarsOutputStream _os) {
    _os.write(iFontColor, 0);
    _os.write(iFontSize, 1);
    _os.write(iPopupStyle, 2);
    _os.write(iNickNameFontColor, 3);
    _os.write(iDarkFontColor, 4);
    _os.write(iDarkNickNameFontColor, 5);
  }

  @override
  void readFrom(TarsInputStream _is) {
    iFontColor = _is.read(iFontColor, 0, false);
    iFontSize = _is.read(iFontSize, 1, false);
    iPopupStyle = _is.read(iPopupStyle, 2, false);
    iNickNameFontColor = _is.read(iNickNameFontColor, 3, false);
    iDarkFontColor = _is.read(iDarkFontColor, 4, false);
    iDarkNickNameFontColor = _is.read(iDarkNickNameFontColor, 5, false);
  }

  @override
  Object deepCopy() => HYContentFormat()
    ..iFontColor = iFontColor
    ..iFontSize = iFontSize
    ..iPopupStyle = iPopupStyle
    ..iNickNameFontColor = iNickNameFontColor
    ..iDarkFontColor = iDarkFontColor
    ..iDarkNickNameFontColor = iDarkNickNameFontColor;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYBulletBorderGroundFormat extends TarsStruct {
  int iEnableUse = 0;
  int iBorderThickness = 0;
  int iBorderColour = -1;
  int iBorderDiaphaneity = 100;
  int iGroundColour = -1;
  int iGroundColourDiaphaneity = 100;
  String sAvatarDecorationUrl = '';
  int iFontColor = -1;
  int iTerminalFlag = -1;

  @override
  void writeTo(TarsOutputStream _os) {
    _os.write(iEnableUse, 0);
    _os.write(iBorderThickness, 1);
    _os.write(iBorderColour, 2);
    _os.write(iBorderDiaphaneity, 3);
    _os.write(iGroundColour, 4);
    _os.write(iGroundColourDiaphaneity, 5);
    _os.write(sAvatarDecorationUrl, 6);
    _os.write(iFontColor, 7);
    _os.write(iTerminalFlag, 8);
  }

  @override
  void readFrom(TarsInputStream _is) {
    iEnableUse = _is.read(iEnableUse, 0, false);
    iBorderThickness = _is.read(iBorderThickness, 1, false);
    iBorderColour = _is.read(iBorderColour, 2, false);
    iBorderDiaphaneity = _is.read(iBorderDiaphaneity, 3, false);
    iGroundColour = _is.read(iGroundColour, 4, false);
    iGroundColourDiaphaneity = _is.read(iGroundColourDiaphaneity, 5, false);
    sAvatarDecorationUrl = _is.read(sAvatarDecorationUrl, 6, false);
    iFontColor = _is.read(iFontColor, 7, false);
    iTerminalFlag = _is.read(iTerminalFlag, 8, false);
  }

  @override
  Object deepCopy() => HYBulletBorderGroundFormat()
    ..iEnableUse = iEnableUse
    ..iBorderThickness = iBorderThickness
    ..iBorderColour = iBorderColour
    ..iBorderDiaphaneity = iBorderDiaphaneity
    ..iGroundColour = iGroundColour
    ..iGroundColourDiaphaneity = iGroundColourDiaphaneity
    ..sAvatarDecorationUrl = sAvatarDecorationUrl
    ..iFontColor = iFontColor
    ..iTerminalFlag = iTerminalFlag;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

/// 发送请求里的弹幕样式。接收侧的 `HYBulletFormat`（`huya_danmaku.dart`）只读颜色，
/// 字段不全，所以这里单独定义。
class HYSendBulletFormat extends TarsStruct {
  int iFontColor = -1;
  int iFontSize = 4;
  int iTextSpeed = 0;
  int iTransitionType = 1;
  int iPopupStyle = 0;
  HYBulletBorderGroundFormat tBorderGroundFormat = HYBulletBorderGroundFormat();
  List<int> vGraduatedColor = [];
  int iAvatarFlag = 0;
  int iAvatarTerminalFlag = -1;

  @override
  void writeTo(TarsOutputStream _os) {
    _os.write(iFontColor, 0);
    _os.write(iFontSize, 1);
    _os.write(iTextSpeed, 2);
    _os.write(iTransitionType, 3);
    _os.write(iPopupStyle, 4);
    _os.write(tBorderGroundFormat, 5);
    _os.write(vGraduatedColor, 6);
    _os.write(iAvatarFlag, 7);
    _os.write(iAvatarTerminalFlag, 8);
  }

  @override
  void readFrom(TarsInputStream _is) {
    iFontColor = _is.read(iFontColor, 0, false);
    iFontSize = _is.read(iFontSize, 1, false);
    iTextSpeed = _is.read(iTextSpeed, 2, false);
    iTransitionType = _is.read(iTransitionType, 3, false);
    iPopupStyle = _is.read(iPopupStyle, 4, false);
    tBorderGroundFormat = _is.readTarsStruct(tBorderGroundFormat, 5, false) as HYBulletBorderGroundFormat;
    iAvatarFlag = _is.read(iAvatarFlag, 7, false);
    iAvatarTerminalFlag = _is.read(iAvatarTerminalFlag, 8, false);
  }

  @override
  Object deepCopy() => HYSendBulletFormat()
    ..iFontColor = iFontColor
    ..iFontSize = iFontSize
    ..iTextSpeed = iTextSpeed
    ..iTransitionType = iTransitionType
    ..iPopupStyle = iPopupStyle
    ..tBorderGroundFormat = tBorderGroundFormat.deepCopy() as HYBulletBorderGroundFormat
    ..vGraduatedColor = List<int>.of(vGraduatedColor)
    ..iAvatarFlag = iAvatarFlag
    ..iAvatarTerminalFlag = iAvatarTerminalFlag;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYSendMessageFormat extends TarsStruct {
  int iSenceType = 0;
  int lFormatId = 0;
  int lSizeTemplateId = 0;

  @override
  void writeTo(TarsOutputStream _os) {
    _os.write(iSenceType, 0);
    _os.write(lFormatId, 1);
    _os.write(lSizeTemplateId, 2);
  }

  @override
  void readFrom(TarsInputStream _is) {
    iSenceType = _is.read(iSenceType, 0, false);
    lFormatId = _is.read(lFormatId, 1, false);
    lSizeTemplateId = _is.read(lSizeTemplateId, 2, false);
  }

  @override
  Object deepCopy() => HYSendMessageFormat()
    ..iSenceType = iSenceType
    ..lFormatId = lFormatId
    ..lSizeTemplateId = lSizeTemplateId;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYSendMessageReq extends TarsStruct {
  HuyaUserId tUserId = HuyaUserId();
  int lTid = 0;
  int lSid = 0;
  String sContent = '';
  int iShowMode = 0;
  HYContentFormat tFormat = HYContentFormat();
  HYSendBulletFormat tBulletFormat = HYSendBulletFormat();
  List<dynamic> vAtSomeone = [];
  int lPid = 0;
  List<dynamic> vTagInfo = [];
  HYSendMessageFormat tSenceFormat = HYSendMessageFormat();
  int iMessageMode = 0;

  @override
  void writeTo(TarsOutputStream _os) {
    _os.write(tUserId, 0);
    _os.write(lTid, 1);
    _os.write(lSid, 2);
    _os.write(sContent, 3);
    _os.write(iShowMode, 4);
    _os.write(tFormat, 5);
    _os.write(tBulletFormat, 6);
    _os.write(vAtSomeone, 7);
    _os.write(lPid, 8);
    _os.write(vTagInfo, 9);
    _os.write(tSenceFormat, 10);
    _os.write(iMessageMode, 11);
  }

  @override
  void readFrom(TarsInputStream _is) {
    tUserId = _is.readTarsStruct(tUserId, 0, false) as HuyaUserId;
    lTid = _is.read(lTid, 1, false);
    lSid = _is.read(lSid, 2, false);
    sContent = _is.read(sContent, 3, false);
    iShowMode = _is.read(iShowMode, 4, false);
    tFormat = _is.readTarsStruct(tFormat, 5, false) as HYContentFormat;
    tBulletFormat = _is.readTarsStruct(tBulletFormat, 6, false) as HYSendBulletFormat;
    lPid = _is.read(lPid, 8, false);
    tSenceFormat = _is.readTarsStruct(tSenceFormat, 10, false) as HYSendMessageFormat;
    iMessageMode = _is.read(iMessageMode, 11, false);
  }

  @override
  Object deepCopy() => HYSendMessageReq()
    ..tUserId = tUserId.deepCopy() as HuyaUserId
    ..lTid = lTid
    ..lSid = lSid
    ..sContent = sContent
    ..iShowMode = iShowMode
    ..tFormat = tFormat.deepCopy() as HYContentFormat
    ..tBulletFormat = tBulletFormat.deepCopy() as HYSendBulletFormat
    ..lPid = lPid
    ..tSenceFormat = tSenceFormat.deepCopy() as HYSendMessageFormat
    ..iMessageMode = iMessageMode;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}
