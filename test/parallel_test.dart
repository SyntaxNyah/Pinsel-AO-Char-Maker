import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/imaging/parallel.dart';

void main() {
  test('preserves input order regardless of completion order', () async {
    final List<int> items = List<int>.generate(10, (int i) => i);
    final List<int> out = await mapParallel<int, int>(
      items,
      (int i) async {
        // Later items finish sooner, so order can only be right if it's tracked.
        await Future<void>.delayed(Duration(milliseconds: 10 - i));
        return i * 2;
      },
      concurrency: 4,
    );
    expect(out, <int>[0, 2, 4, 6, 8, 10, 12, 14, 16, 18]);
  });

  test('runs every item exactly once', () async {
    final List<int> seen = <int>[];
    await mapParallel<int, void>(
      List<int>.generate(20, (int i) => i),
      (int i) async => seen.add(i),
      concurrency: 5,
    );
    seen.sort();
    expect(seen, List<int>.generate(20, (int i) => i));
  });

  test('never exceeds the concurrency cap', () async {
    int active = 0, peak = 0;
    await mapParallel<int, int>(
      List<int>.generate(12, (int i) => i),
      (int i) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return i;
      },
      concurrency: 3,
    );
    expect(peak, lessThanOrEqualTo(3));
  });

  test('concurrency < 1 collapses to a single lane', () async {
    int active = 0, peak = 0;
    await mapParallel<int, int>(
      List<int>.generate(5, (int i) => i),
      (int i) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return i;
      },
      concurrency: 0,
    );
    expect(peak, 1);
  });

  test('empty input returns empty', () async {
    expect(await mapParallel<int, int>(<int>[], (int i) async => i), isEmpty);
  });
}
