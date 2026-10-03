import 'dart:ui';
import 'barrage_item.dart';
import '../../cache/render_cache.dart';
import '../../effect/motion/barrage_motion_effect.dart';

/// Runtime state of one message that is (or is about to be) on screen.
///
/// Instances are pooled: the engine obtains them from [BarragePool.obtain]
/// and returns them via resettable fields, so this class intentionally uses
/// mutable fields instead of finals. The [reset] contract is that every
/// field must return to a defined initial value — when adding a field here,
/// remember to clear it in [reset] as well.
class BarrageEntry {
  BarrageEntry({required this.item, required this.creationTime});

  /// The immutable message being displayed.
  BarrageItem item;

  /// Engine time at which the entry object was created, in milliseconds.
  int creationTime;

  // =========================
  // Position
  // =========================
  /// Screen-space position and size of the laid-out content, in logical
  /// pixels. [x]/[y] are the top-left corner of the content bounds.
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;

  /// Index of the lane this entry occupies; -1 before dispatch.
  int track = -1;

  /// Scroll velocity in logical pixels per second; always 0 for fixed types.
  double speed = 0;

  /// Entries are removed from the active list the same frame they turn
  /// inactive, so anything inside the list is expected to be active.
  bool active = true;

  /// Held in place by the host (e.g. a tap opened an action sheet). While
  /// paused the entry neither moves nor expires; time spent paused is not
  /// counted against pinned dwell time.
  bool paused = false;

  // =========================
  // Timing
  // =========================

  /// Engine time the message was dispatched to a lane, in milliseconds.
  int spawnTime = 0;

  /// Engine time at which a fixed message expires, in milliseconds. Scroll
  /// messages leave the screen by moving out of view instead.
  int expireTime = 0;

  /// Logical time of the last position integration, in milliseconds with
  /// sub-millisecond precision. Motion deltas are computed against it.
  double lastUpdateTime = 0;

  // =========================
  // Render artifacts
  // =========================

  /// Unused. Layout paragraphs live on the [LayoutSpan]s owned by the
  /// layout cache; these fields predate that design and are kept only for
  /// source compatibility.
  Paragraph? paragraph;
  Paragraph? strokeParagraph;

  /// Vector recording used when no rasterized bitmap is available. Points at
  /// the shared [CachedRender.picture]; never disposed from here.
  Picture? picture;
  String? pictureCacheKey;

  /// Shared render artifact backing [picture] and [image]. The engine holds
  /// one reference claim for the lifetime of the entry and must hand it back
  /// to the render cache on recycle.
  CachedRender? render;

  /// Motion-effect show state. Non-null only while a [BarrageMotionEffect]
  /// owns this entry's choreography: the motion system advances it, the
  /// render system applies its transform, and the effect drives x/y itself
  /// instead of the default scroll/fixed movement.
  BarrageFxState? fx;

  double? cachedWidth;

  // =========================
  // reset
  // =========================
  /// Returns the entry to a clean state before it is handed out again.
  /// Every field above must be covered here.
  void reset({required BarrageItem newItem, required int newCreationTime}) {
    item = newItem;

    creationTime = newCreationTime;

    x = 0;
    y = 0;
    width = 0;
    height = 0;

    track = -1;
    speed = 0;
    active = true;
    paused = false;

    spawnTime = 0;
    expireTime = 0;
    lastUpdateTime = 0;

    paragraph = null;
    strokeParagraph = null;
    picture = null;
    pictureCacheKey = null;
    render = null;
    fx = null;
    cachedWidth = null;
  }
}
