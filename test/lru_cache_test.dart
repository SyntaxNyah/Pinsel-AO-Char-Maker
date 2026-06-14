import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/core/lru_cache.dart';

void main() {
  group('LruCache', () {
    test('keeps at most `capacity` entries, evicting the oldest', () {
      final LruCache<String, int> c = LruCache<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      c['c'] = 3; // evicts 'a' (least recently used)
      expect(c.length, 2);
      expect(c.containsKey('a'), isFalse);
      expect(c['b'], 2);
      expect(c['c'], 3);
    });

    test('a read marks a key most-recently-used (so it survives eviction)', () {
      final LruCache<String, int> c = LruCache<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      expect(c['a'], 1); // touch 'a' → now 'b' is the oldest
      c['c'] = 3; // evicts 'b', not 'a'
      expect(c.containsKey('a'), isTrue);
      expect(c.containsKey('b'), isFalse);
      expect(c.containsKey('c'), isTrue);
    });

    test('re-writing a key refreshes its recency', () {
      final LruCache<String, int> c = LruCache<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      c['a'] = 10; // update + bump 'a'
      c['c'] = 3; // evicts 'b'
      expect(c['a'], 10);
      expect(c.containsKey('b'), isFalse);
    });

    test('stores and distinguishes null values', () {
      final LruCache<String, int?> c = LruCache<String, int?>(4);
      c['x'] = null; // remember a "failed" lookup
      expect(c.containsKey('x'), isTrue);
      expect(c['x'], isNull);
      expect(c.containsKey('y'), isFalse);
    });

    test('clear empties it', () {
      final LruCache<String, int> c = LruCache<String, int>(4);
      c['a'] = 1;
      c['b'] = 2;
      c.clear();
      expect(c.length, 0);
      expect(c.containsKey('a'), isFalse);
    });
  });
}
