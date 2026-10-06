import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/player/core/live_room_volume_manager.dart';

void main() {
  group('播放引擎自己的音量', () {
    test('手机上固定满刻度：响度只由设备的媒体音量决定', () {
      // 房间名下记过什么值都不该再压一层；以前这里会把 0.5 的默认值或一次系统音量
      // 快照设给引擎，和设备音量相乘。
      for (final roomVolume in [0.0, 0.3, 0.5, 1.0]) {
        expect(
          LiveRoomVolumeManager.resolveEngineVolume(muted: false, deviceOwnsLoudness: true, roomVolume: roomVolume),
          1.0,
          reason: 'roomVolume=$roomVolume',
        );
      }
    });

    test('桌面端没有设备音量这一层，用房间保存的音量', () {
      expect(LiveRoomVolumeManager.resolveEngineVolume(muted: false, deviceOwnsLoudness: false, roomVolume: 0.3), 0.3);
      expect(LiveRoomVolumeManager.resolveEngineVolume(muted: false, deviceOwnsLoudness: false, roomVolume: 1.0), 1.0);
    });

    test('全局静音时引擎音量是 0，手机和桌面都一样', () {
      for (final deviceOwnsLoudness in [true, false]) {
        expect(
          LiveRoomVolumeManager.resolveEngineVolume(
            muted: true,
            deviceOwnsLoudness: deviceOwnsLoudness,
            roomVolume: 0.8,
          ),
          0.0,
        );
      }
    });

    test('房间音量越界或不是有限值时收进合法范围', () {
      expect(LiveRoomVolumeManager.resolveEngineVolume(muted: false, deviceOwnsLoudness: false, roomVolume: 1.7), 1.0);
      expect(LiveRoomVolumeManager.resolveEngineVolume(muted: false, deviceOwnsLoudness: false, roomVolume: -1), 0.0);
      expect(
        LiveRoomVolumeManager.resolveEngineVolume(muted: false, deviceOwnsLoudness: false, roomVolume: double.nan),
        1.0,
      );
    });
  });
}
