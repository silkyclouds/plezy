/// Runs [task] over [items] with at most [limit] calls in flight and returns the results in input order.
Future<List<R>> rtbfMapLimited<T, R>(List<T> items, Future<R> Function(T item) task, {int limit = 4}) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (next < items.length) {
      final index = next++;
      results[index] = await task(items[index]);
    }
  }

  final workers = limit < items.length ? limit : items.length;
  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  return [for (final r in results) r as R];
}
