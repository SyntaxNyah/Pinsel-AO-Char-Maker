import 'cpu_io.dart' if (dart.library.html) 'cpu_web.dart' as impl;

/// Number of logical CPU cores available for parallel image baking.
///
///  * Native: the real processor count (`Platform.numberOfProcessors`).
///  * Web: the browser's `navigator.hardwareConcurrency`, or a safe default.
///
/// Used to decide how many render/encode jobs to keep in flight at once (see
/// `imaging/parallel.dart`). On web heavy work runs inline, so the figure there
/// is only an upper bound, never a guarantee of true parallelism.
int get cpuCount {
  final int n = impl.cpuCount;
  return n < 1 ? 1 : n;
}
