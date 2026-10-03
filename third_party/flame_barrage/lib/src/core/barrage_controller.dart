import '../model/barrage/barrage_item.dart';
import 'barrage_config.dart';
import 'barrage_engine_api.dart';

/// Type-safe facade between host application code and the engine.
///
/// Business code talks to [BarrageController] only ([send], [pause],
/// [resume], [clear], [updateConfig]); every call is forwarded to the
/// [BarrageEngineApi] implementation currently attached. The interface makes
/// the forwarding statically checked, so a signature drift between the two
/// sides fails analysis instead of surfacing as a runtime cast error.
class BarrageController {
  BarrageEngineApi? _engine;

  bool running = true;
  int _totalEmittedCount = 0;

  BarrageEngineApi? get engine => _engine;

  void attach(BarrageEngineApi engine) => _engine = engine;

  void detach([BarrageEngineApi? engine]) {
    if (engine != null && !identical(_engine, engine)) return;
    _engine = null;
  }

  void send(BarrageItem item) {
    if (!running) return;
    _totalEmittedCount++;
    _engine?.pushMessage(item);
  }

  void updateConfig(BarrageConfig newConfig) => _engine?.updateConfig(newConfig);

  void togglePause() {
    if (running) {
      pause();
    } else {
      resume();
    }
  }

  void pause() {
    running = false;
    _engine?.pause();
  }

  void resume() {
    running = true;
    _engine?.resume();
  }

  void clear() => _engine?.clear();

  /// Takes back every message matching [predicate] — on screen, waiting for a
  /// lane, or parked in the pause buffer (host-side retraction: the platform
  /// recalled a chat message). Returns how many were taken back.
  int retractWhere(bool Function(BarrageItem item) predicate) => _engine?.retractWhere(predicate) ?? 0;

  bool triggerItemAt(double x, double y, {required bool longPress}) {
    return _engine?.triggerItemAt(x, y, longPress: longPress) ?? false;
  }

  /// Holds the top-most message at the point in place (it neither scrolls nor
  /// expires) and returns it, so the host can present an action sheet on it.
  /// Returns null when the point hits nothing.
  BarrageItem? pauseItemAt(double x, double y) => _engine?.pauseItemAt(x, y);

  /// Releases every held message; they continue from where they froze.
  void resumeAllPaused() => _engine?.resumeAllPaused();

  /// Number of messages currently held in place.
  int get pausedCount => _engine?.pausedCount ?? 0;

  int get totalEmitted => _totalEmittedCount;

  int get pictureCacheCount => _engine?.activeCacheSize ?? 0;

  int get poolObjectCount => _engine?.activePoolSize ?? 0;

  int get pendingMessageCount => _engine?.pendingMessageCount ?? 0;

  /// Messages currently on screen, which is what a frame actually pays for.
  int get activeItemCount => _engine?.activeCount ?? 0;

  /// GPU memory held by the rasterized message bitmaps, in bytes.
  int get rasterCacheBytes => _engine?.rasterCacheBytes ?? 0;
}
