/// A tiny **capacity-bounded LRU map**: keeps at most [capacity] entries and
/// evicts the least-recently-used one on overflow. Both reads (`[]`) and writes
/// (`[]=`) mark a key as most-recently-used.
///
/// This is the **memory ceiling** behind the app's decode / preview / thumbnail
/// caches: without a bound, browsing a big cast (hundreds of sprites) fills those
/// maps with full-resolution decoded frames until the OS kills the app. A bounded
/// cache trades a re-decode on a cold key for a hard cap on resident memory.
///
/// A plain Dart `Map` is insertion-ordered, so `keys.first` is always the oldest
/// touched entry — no `dart:collection` import or linked list needed. `null`
/// values are supported (the decode cache stores `null` to remember a *failed*
/// decode, so [containsKey] must distinguish "cached null" from "absent").
class LruCache<K, V> {
  LruCache(this.capacity) : assert(capacity > 0, 'capacity must be > 0');

  final int capacity;
  final Map<K, V> _m = <K, V>{};

  int get length => _m.length;

  bool containsKey(K key) => _m.containsKey(key);

  /// The value for [key], or `null` if absent. A hit moves the key to
  /// most-recently-used. (A stored `null` value also returns `null`; use
  /// [containsKey] to tell them apart.)
  V? operator [](K key) {
    if (!_m.containsKey(key)) return null;
    final V v = _m.remove(key) as V; // re-insert at the end = most recent
    _m[key] = v;
    return v;
  }

  /// Insert/update [key], marking it most-recently-used, then evict the
  /// oldest entries until at most [capacity] remain.
  void operator []=(K key, V value) {
    _m.remove(key);
    _m[key] = value;
    while (_m.length > capacity) {
      _m.remove(_m.keys.first);
    }
  }

  V? remove(K key) => _m.remove(key);

  void clear() => _m.clear();
}
