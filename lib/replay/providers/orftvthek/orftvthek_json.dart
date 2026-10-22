/// A JSON object, or null when [value] is anything else.
Map<String, dynamic>? orfMap(Object? value) => value is Map<String, dynamic> ? value : null;

/// The objects of a JSON array; entries that are not objects are dropped.
List<Map<String, dynamic>> orfMaps(Object? value) => value is List
    ? [
        for (final entry in value)
          if (entry is Map<String, dynamic>) entry,
      ]
    : const [];

/// A trimmed, non-empty string, or null.
String? orfString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A whole number, from a JSON number or a numeric string (ORF sends page counters as strings).
int? orfInt(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

/// An ISO 8601 timestamp with offset, as UTC.
DateTime? orfDate(Object? value) => value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// The entries of a list reply: HAL lists use `_embedded.items`, lanes and topics use `_items`.
List<Map<String, dynamic>> orfItems(Map<String, dynamic> page) =>
    orfMaps(orfMap(page['_embedded'])?['items'] ?? page['_items']);

/// The size of the whole list behind a page.
int? orfTotal(Map<String, dynamic> page) => orfInt(page['total']);

/// The numeric id at the end of a resource link such as `.../profile/1203`.
int? orfIdFromLink(Object? link) {
  final href = orfString(orfMap(link)?['href']);
  if (href == null) return null;
  return int.tryParse(href.substring(href.lastIndexOf('/') + 1));
}
