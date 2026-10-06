import 'dart:io';

import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/core/config/volume_settings_controller.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/config/settings_service.dart';

class LiveRoomVolumeManager {
  static String _getVolumeKey(LiveRoom liveroom) {
    final roomId = liveroom.roomId ?? '';
    final platform = liveroom.platform ?? '';
    return "room_vol_${platform.toLowerCase().trim()}_${roomId.trim()}";
  }

  static double getRoomVolume(LiveRoom liveroom) {
    if (SettingsService.to.vol.globalVolumeMute.v) return 0.0;

    final key = _getVolumeKey(liveroom);
    final volume = SettingsService.to.vol.roomVolumes[key];

    if (volume != null && volume.isFinite) return volume.clamp(0.0, 1.0).toDouble();

    return Platform.isAndroid || Platform.isIOS
        ? VolumeSettingsController.normalizeVolume(SettingsService.to.vol.defaultMobileVolume.v, fallback: 0.5)
        : VolumeSettingsController.normalizeVolume(SettingsService.to.vol.defaultDesktopVolume.v, fallback: 1.0);
  }

  /// Whether loudness is set with the device's media volume (the hardware keys
  /// and the in-room gesture and slider all drive it) rather than with the
  /// player engine's own volume.
  static bool get deviceOwnsLoudness => Platform.isAndroid || Platform.isIOS;

  /// The player engine's own volume for [liveroom].
  static double getEngineVolume(LiveRoom liveroom) => resolveEngineVolume(
    muted: SettingsService.to.vol.globalVolumeMute.v,
    deviceOwnsLoudness: deviceOwnsLoudness,
    roomVolume: getRoomVolume(liveroom),
  );

  /// Where the device's media volume sets loudness the engine stays at full
  /// scale: scaling it as well put a second attenuation, with no control of
  /// its own, on top of the device level. Elsewhere it is the room's volume.
  static double resolveEngineVolume({
    required bool muted,
    required bool deviceOwnsLoudness,
    required double roomVolume,
  }) {
    if (muted) return 0.0;
    if (deviceOwnsLoudness || !roomVolume.isFinite) return 1.0;
    return roomVolume.clamp(0.0, 1.0).toDouble();
  }

  static Future<void> saveRoomVolume(LiveRoom liveroom, double volume) async {
    if (!volume.isFinite) return;
    final key = _getVolumeKey(liveroom);
    final newMap = Map<String, double>.from(SettingsService.to.vol.roomVolumes);
    newMap[key] = volume.clamp(0.0, 1.0).toDouble();
    SettingsService.to.vol.roomVolumes = newMap;
  }
}
