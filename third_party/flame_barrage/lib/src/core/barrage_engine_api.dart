import '../model/barrage/barrage_item.dart';
import 'barrage_config.dart';

/// Contract for the danmaku engine's host-facing capabilities.
///
/// [BarrageController] forwards calls through this interface, so the widget
/// layer never depends on a concrete engine class and alternative engine
/// implementations can be swapped in behind the same controller.
abstract class BarrageEngineApi {
  /// Enqueues one message for dispatch.
  void pushMessage(BarrageItem item);

  /// Hot-applies engine configuration (cache budgets, lane geometry, frame
  /// rate, dispatch pacing). On-screen messages are re-laid out immediately
  /// when the change affects what they look like or where they sit.
  void updateConfig(BarrageConfig config);

  /// Stops advancing. Incoming messages accumulate in a pause buffer instead
  /// of being dropped.
  void pause();

  /// Resumes advancing.
  void resume();

  /// Releases every entry, queue and cached artifact.
  void clear();

  /// Takes back every message — on screen or still waiting for a lane — whose
  /// [BarrageItem] matches [predicate] (host-side retraction: the platform
  /// recalled a chat message). Returns how many were taken back.
  int retractWhere(bool Function(BarrageItem item) predicate);

  /// Hit-tests the point and fires the matching message's tap or long-press
  /// callback. Returns true when a message was hit and the callback fired.
  bool triggerItemAt(double x, double y, {required bool longPress});

  /// Hit-tests the point and holds the top-most message in place. The paused
  /// message neither scrolls nor expires until [resumeAllPaused] runs, so the
  /// host can open an action sheet (block / report / like) on it. Returns the
  /// held message, or null when nothing was hit.
  BarrageItem? pauseItemAt(double x, double y);

  /// Releases every message held by [pauseItemAt]; they continue from the
  /// exact position they were frozen at.
  void resumeAllPaused();

  /// Number of messages currently held in place.
  int get pausedCount;

  /// Number of entries held in the render cache.
  int get activeCacheSize;

  /// Number of messages currently on screen — the count a display frame
  /// actually pays for.
  int get activeCount;

  /// Approximate GPU memory held by the rasterized message bitmaps, in bytes.
  int get rasterCacheBytes;

  /// Number of entry objects parked in the pool.
  int get activePoolSize;

  /// Number of messages waiting for a lane, including the pause buffer.
  int get pendingMessageCount;

  /// Whether on-screen messages are drawn as baked bitmaps rather than
  /// replayed vector recordings.
  bool get rasterizationActive;
}
