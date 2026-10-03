import 'dart:collection';
import 'dart:ui' as ui;

/// One cached rendering of a message body, shared by every barrage that
/// happens to have the same appearance key.
///
/// [picture] is the vector display list and is always present. [image] is the
/// optional rasterized copy of it, and it is the reason a busy scene can hold
/// its frame time on weak hardware: drawing the image costs one textured quad,
/// while drawing [picture] replays every text, stroke, shadow and emoji
/// operation — and a stroked glyph run is re-tessellated by the raster thread
/// on every single one of those replays.
class CachedRender {
  CachedRender({required this.picture});

  final ui.Picture picture;

  /// Rasterized copy of [picture], null while rasterization is unavailable.
  ui.Image? image;

  /// The picture used to produce [image]. Kept so it is released together with
  /// the image instead of depending on how the engine holds display lists.
  ui.Picture? rasterSource;

  /// Transparent padding baked around the content, in logical pixels. Strokes,
  /// glows and shadows extend past the text bounds and must not be clipped.
  double padding = 0;

  /// Logical size of the baked region (content plus padding).
  double rasterWidth = 0;
  double rasterHeight = 0;

  /// Source rectangle of [image], in pixels, matching [rasterWidth] exactly.
  ui.Rect rasterSrc = ui.Rect.zero;

  /// True when one logical pixel maps to one image pixel, which lets a frame
  /// blit the image instead of scaling it.
  bool oneToOne = true;

  /// Owners: one for [RenderCache] plus one per active entry drawing it.
  int _owners = 0;
  bool _disposed = false;

  bool get hasImage => image != null;
  bool get isDisposed => _disposed;

  /// Approximate GPU memory held by this entry.
  int get byteSize {
    final current = image;
    if (current == null) return 0;
    return current.width * current.height * 4;
  }

  void retain() => _owners++;

  void release() {
    if (_owners > 0) _owners--;
    if (_owners == 0) dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image?.dispose();
    image = null;
    rasterSource?.dispose();
    rasterSource = null;
    picture.dispose();
  }
}

/// LRU cache of [CachedRender] artifacts.
///
/// Disposal is reference counted: an evicted entry that a visible barrage is
/// still drawing stays alive until that barrage is recycled. Disposing a
/// Picture or Image out from under a visible message threw on every following
/// frame — a stream with more distinct messages than the cache holds could
/// therefore stutter far worse than the raw drawing cost suggests.
class RenderCache {
  RenderCache({required this.maxSize, required this.maxBytes});

  int maxSize;
  int maxBytes;

  /// Cleared when the platform refuses to rasterize pictures, so the engine
  /// stops paying for a failed attempt on every dispatch.
  bool rasterizationSupported = true;

  final LinkedHashMap<String, CachedRender> _entries = LinkedHashMap<String, CachedRender>();
  int _bytes = 0;

  int get size => _entries.length;

  /// Approximate GPU memory held by the cache, in bytes.
  int get byteSize => _bytes;

  /// Returns the entry for [key] with one owner for the caller, or null on a
  /// miss. Release it when the barrage stops drawing it.
  CachedRender? acquire(String key) {
    final render = _entries.remove(key);
    if (render == null) return null;
    _entries[key] = render;
    render.retain();
    return render;
  }

  /// Inserts [render] under [key] and returns it with one owner for the caller,
  /// exactly like [acquire].
  ///
  /// Every caller gets its own owner, which is what keeps an evicted entry alive
  /// while a visible barrage still draws it: the cache dropping its entry must
  /// never dispose a Picture or Image that a frame is about to use. Bake the
  /// image before calling this — the byte budget is accounted at insert time.
  CachedRender put(String key, CachedRender render) {
    // Taken before the insert so no eviction running inside can dispose what is
    // handed back to the caller.
    render.retain();
    final previous = _entries.remove(key);
    if (previous != null) _forget(previous);
    _entries[key] = render;
    render.retain();
    _bytes += render.byteSize;
    _trim(keep: key);
    return render;
  }

  /// Drops the owner an [acquire] or [put] handed to the caller.
  void release(CachedRender? render) => render?.release();

  void updateLimits({int? maxSize, int? maxBytes}) {
    if (maxSize != null && maxSize > 0) this.maxSize = maxSize;
    if (maxBytes != null && maxBytes > 0) this.maxBytes = maxBytes;
    _trim();
  }

  /// Drops every entry. Entries still drawn by a live barrage are disposed as
  /// soon as that barrage is released.
  void clear() {
    for (final render in _entries.values) {
      _forget(render);
    }
    _entries.clear();
    _bytes = 0;
  }

  void _forget(CachedRender render) {
    _bytes -= render.byteSize;
    if (_bytes < 0) _bytes = 0;
    render.release();
  }

  void _trim({String? keep}) {
    if (_entries.length <= maxSize && _bytes <= maxBytes) return;
    for (final key in _entries.keys.toList(growable: false)) {
      if (_entries.length <= maxSize && _bytes <= maxBytes) break;
      if (key == keep) continue;
      final evicted = _entries.remove(key);
      if (evicted != null) _forget(evicted);
    }
  }
}
