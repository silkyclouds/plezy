/// The items of a catalogue answer: `resposta.items.item`, which is a single object when only one matched.
List<Map<String, dynamic>> threeCatItems(Map<String, dynamic> answer) {
  final items = (answer['resposta'] as Map?)?['items'];
  final item = items is Map ? items['item'] : null;
  if (item is List) return item.whereType<Map<String, dynamic>>().toList();
  return item is Map<String, dynamic> ? [item] : const [];
}

/// The single object of a one-item answer such as `programestv/{id}/`.
Map<String, dynamic>? threeCatItem(Map<String, dynamic> answer) {
  final item = (answer['resposta'] as Map?)?['item'];
  return item is Map<String, dynamic> ? item : null;
}

/// How many items and pages the full result has.
({int totalItems, int totalPages}) threeCatPaging(Map<String, dynamic> answer) {
  final paging = (answer['resposta'] as Map?)?['paginacio'];
  final items = paging is Map ? (paging['total_items'] as num?)?.toInt() : null;
  final pages = paging is Map ? (paging['total_pagines'] as num?)?.toInt() : null;
  return (totalItems: items ?? threeCatItems(answer).length, totalPages: pages ?? 1);
}
