import 'dart:ui';
import 'dart:collection';

class PicturePool {
  PicturePool({this.maxSize = 50});

  final int maxSize;
  final Map<String, Picture> _cache = {};
  // A List with removeAt(0) shifts every remaining element on each eviction
  // (O(n) per put once the pool is full). A Queue evicts from the front in
  // O(1), which matters once this pool churns under a busy stream.
  final Queue<String> _keys = Queue<String>();

  Picture? get(String key) {
    return _cache[key];
  }

  void put(String key, Picture picture) {
    if (_cache.containsKey(key)) {
      return;
    }
    if (_cache.length >= maxSize) {
      final oldKey = _keys.removeFirst();
      _cache.remove(oldKey)?.dispose();
    }
    _cache[key] = picture;
    _keys.addLast(key);
  }

  void clear() {
    for (final pic in _cache.values) {
      pic.dispose();
    }
    _cache.clear();
    _keys.clear();
  }
}
