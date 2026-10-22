/// The `items` of an RTVE page envelope, without entries that are not objects.
List<Map<String, dynamic>> rtveItems(Map<String, dynamic> body) {
  final items = (body['page'] as Map?)?['items'];
  if (items is! List) return const [];
  return items.whereType<Map<String, dynamic>>().toList();
}

/// The total RTVE reports for the whole list behind a page, or [fallback] when it reports none.
int rtveTotal(Map<String, dynamic> body, {int fallback = 0}) =>
    ((body['page'] as Map?)?['total'] as num?)?.toInt() ?? fallback;

/// How many pages the list behind a page has.
int rtveTotalPages(Map<String, dynamic> body) => ((body['page'] as Map?)?['totalPages'] as num?)?.toInt() ?? 1;
