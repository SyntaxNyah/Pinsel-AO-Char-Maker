/// Small, pure-Dart concurrency helper used to spread heavy image baking across
/// many CPU cores.
///
/// It does NOT spawn isolates itself — the *task* decides whether to run on a
/// background isolate (via Flutter's `compute`) or inline. This keeps the helper
/// dependency-free (no `package:flutter`, no `dart:isolate`), so it works on
/// every platform (including web, where it degrades to ordered, cooperative
/// scheduling) and is trivially unit-testable.
///
/// Order is preserved: `results[i]` always corresponds to `items[i]`, regardless
/// of which lane finished first.
library;

/// Run [task] over [items] keeping at most [concurrency] futures in flight at
/// once. Results are returned in input order.
///
/// When each [task] dispatches to a background isolate (e.g. `compute`), this
/// gives true multi-core parallelism: with [concurrency] = CPU count, N sprites
/// encode on N cores at once instead of one-at-a-time.
///
/// [onProgress] fires once per completed item with `(done, total)` — note it is
/// called in completion order, not input order, so use it only for a progress
/// count, not to index back into [items].
Future<List<R>> mapParallel<T, R>(
  List<T> items,
  Future<R> Function(T item) task, {
  int concurrency = 4,
  void Function(int done, int total)? onProgress,
}) async {
  final int total = items.length;
  if (total == 0) return <R>[];

  final int lanes =
      concurrency < 1 ? 1 : (concurrency > total ? total : concurrency);
  final List<R?> results = List<R?>.filled(total, null);
  int next = 0;
  int done = 0;

  Future<void> runLane() async {
    while (true) {
      final int i = next;
      if (i >= total) break;
      next++;
      results[i] = await task(items[i]);
      done++;
      onProgress?.call(done, total);
    }
  }

  await Future.wait<void>(<Future<void>>[
    for (int k = 0; k < lanes; k++) runLane(),
  ]);
  return results.cast<R>();
}
