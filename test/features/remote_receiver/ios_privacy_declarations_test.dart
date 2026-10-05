import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';

// iOS 对没有声明用途的隐私能力不是报错而是直接终止进程，对没有声明的 Bonjour
// 服务类型则是拒绝广播和发现。这些声明和用到它们的 Dart 代码分在两处，这里把
// 两边绑在一起。
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  String? stringFor(String key) =>
      RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(plist)?.group(1)?.trim();

  List<String> arrayFor(String key) {
    final body = RegExp('<key>$key</key>\\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist)?.group(1);
    if (body == null) return const [];
    return [for (final match in RegExp('<string>([^<]*)</string>').allMatches(body)) match.group(1)!.trim()];
  }

  test('the QR scanner pages may ask for the camera', () {
    // 设备同步的扫码页和“同步 TV 数据”都会打开相机。
    expect(stringFor('NSCameraUsageDescription'), isNotEmpty);
  });

  test('device sync may advertise and browse its Bonjour service', () {
    expect(arrayFor('NSBonjourServices'), contains(RemoteSyncService.mdnsServiceType));
    expect(stringFor('NSLocalNetworkUsageDescription'), isNotEmpty);
  });
}
