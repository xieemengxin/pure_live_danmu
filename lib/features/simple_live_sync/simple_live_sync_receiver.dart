import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/local_network_access.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/features/simple_live_sync/simple_live_sync_protocol.dart';

/// Makes this device show up as a receiver in Simple Live's LAN sync for as
/// long as its page is open, and takes in the kinds the viewer switched on.
///
/// The protocol has no authentication, so the server only runs while the page
/// is on screen and never deletes anything on a remote request.
class SimpleLiveSyncReceiver extends GetxController implements SimpleLiveSyncSink {
  static const int _maxBodyBytes = 16 * 1024 * 1024;

  final RxBool running = false.obs;

  /// i18n key of the reason the server could not start; empty when it did.
  final RxString errorKey = ''.obs;
  final RxList<String> addresses = <String>[].obs;
  final RxList<SimpleLiveSyncEvent> events = <SimpleLiveSyncEvent>[].obs;

  final RxBool acceptFollows = true.obs;
  final RxBool acceptShieldWords = true.obs;
  final RxBool acceptBulletMagazine = true.obs;

  late final SimpleLiveSyncProtocol _protocol = SimpleLiveSyncProtocol(
    sink: this,
    accepts: (kind) => switch (kind) {
      SimpleLiveSyncKind.follows => acceptFollows.value,
      SimpleLiveSyncKind.shieldWords => acceptShieldWords.value,
      SimpleLiveSyncKind.bulletMagazine => acceptBulletMagazine.value,
    },
    onReceived: (event) => events.insert(0, event),
  );

  final String _deviceId = List<String>.generate(8, (_) => Random().nextInt(16).toRadixString(16)).join();
  HttpServer? _server;
  RawDatagramSocket? _discovery;
  bool _closed = false;

  String get _deviceType => Platform.operatingSystem;

  /// What Simple Live's scanner expects in a QR code: the bare address, or
  /// several joined by `;`.
  String get qrPayload => addresses.join(';');

  @override
  void onInit() {
    super.onInit();
    unawaited(start());
  }

  Future<void> start() async {
    if (_server != null || _closed) return;
    errorKey.value = '';
    await LocalNetworkAccess.ensure();
    await _refreshAddresses();
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, SimpleLiveSyncProtocol.httpPort, shared: true);
      if (_closed) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen(_handleRequest, onError: (Object _) {});
      running.value = true;
    } on SocketException {
      // Simple Live 的发送端只连这个固定端口，换端口没有意义。
      errorKey.value = 'simple_live_sync_port_busy';
      return;
    }
    await _startDiscovery();
    _primeLocalNetworkAccess();
  }

  Future<void> _refreshAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      final found = <String>[
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (!address.isLinkLocal) address.address,
      ];
      addresses.assignAll(found.toSet());
    } catch (_) {
      addresses.clear();
    }
  }

  /// Lets Simple Live list this device by itself. Platforms that do not hand
  /// broadcasts to apps (iOS without the multicast entitlement) simply never
  /// hear the probe; the address and QR code still work there.
  Future<void> _startDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        SimpleLiveSyncProtocol.udpPort,
        reuseAddress: true,
      );
      if (_closed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _discovery = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final reply = SimpleLiveSyncProtocol.discoveryReply(
          String.fromCharCodes(datagram.data),
          id: _deviceId,
          type: _deviceType,
          name: 'Pure Live',
        );
        if (reply == null) return;
        try {
          socket.send(reply.codeUnits, InternetAddress('255.255.255.255'), SimpleLiveSyncProtocol.udpPort);
        } catch (_) {}
      }, onError: (Object _) {});
    } catch (_) {
      // 发现只是锦上添花，起不来不影响手动输入地址。
    }
  }

  /// iOS and macOS only ask for local-network access when the app reaches out
  /// to the LAN; a server that merely listens never triggers the prompt and
  /// its incoming connections stay blocked. One datagram to the gateway's
  /// discard port brings the prompt up.
  void _primeLocalNetworkAccess() {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    final socket = _discovery;
    if (socket == null || addresses.isEmpty) return;
    final parts = addresses.first.split('.');
    if (parts.length != 4) return;
    try {
      socket.send(const <int>[0], InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.1'), 9);
    } catch (_) {}
  }

  Future<void> _handleRequest(HttpRequest request) async {
    Object reply;
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/info') {
        reply = SimpleLiveSyncProtocol.info(
          id: _deviceId,
          type: _deviceType,
          name: 'Pure Live',
          version: VersionUtil.version,
          address: qrPayload,
        );
      } else if (request.method == 'GET') {
        reply = <String, Object>{'status': true, 'message': 'http server is running...', 'version': 'Pure Live'};
      } else if (request.method == 'POST') {
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > _maxBodyBytes) throw const FormatException('body too large');
        }
        reply = (await _protocol.handlePost(path, utf8.decode(bytes, allowMalformed: true))).toJson();
      } else {
        reply = const SimpleLiveSyncReply.refused('Pure Live 不支持这项同步').toJson();
      }
    } catch (_) {
      reply = const SimpleLiveSyncReply.refused('Pure Live 处理失败').toJson();
    }
    try {
      // 发送端只认 2xx 加 JSON 类型的响应，失败也要这样回，它才显示得出原因。
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply));
      await request.response.close();
    } catch (_) {}
  }

  @override
  Future<int> addFollows(List<LiveRoom> rooms) async {
    var added = 0;
    final changed = await FavoriteRoomController.to.mutateRoomsDurably((current) {
      final known = current.map((room) => room.identityKey).toSet();
      final merged = List<LiveRoom>.of(current);
      added = 0;
      for (final room in rooms) {
        if (known.add(room.identityKey)) {
          merged.add(room);
          added++;
        }
      }
      return merged;
    });
    return changed ? added : 0;
  }

  @override
  int addShieldWords(List<String> words) {
    final favorites = FavoriteRoomController.to;
    var added = 0;
    for (final word in words) {
      if (favorites.addShieldList(word)) added++;
    }
    return added;
  }

  @override
  void setBulletMagazine(List<String> presets) {
    SettingsService.to.danmaku.bulletMagazinePresets.v = presets;
  }

  @override
  void onClose() {
    _closed = true;
    running.value = false;
    unawaited(_server?.close(force: true));
    _server = null;
    _discovery?.close();
    _discovery = null;
    super.onClose();
  }
}
