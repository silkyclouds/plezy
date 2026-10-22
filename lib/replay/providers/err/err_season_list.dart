/// One season of a show as ERR lists it: a numbered season, the only list of a short series, or a year made of months.
class ErrSeasonEntry {
  final int key;
  final String? name;
  final int firstContentId;

  /// Episodes, present only for the season the page was opened on; ERR leaves the others to a second request.
  final List<Map<String, dynamic>>? contents;

  /// The months of a year, for shows ERR files by date. Empty for every other kind.
  final List<ErrSeasonEntry> months;

  const ErrSeasonEntry({
    required this.key,
    required this.name,
    required this.firstContentId,
    required this.contents,
    required this.months,
  });

  bool get isYear => months.isNotEmpty;
}

/// The `seasonList` block of a content page.
///
/// `seasonal` lists have one entry per season, `shortSeriesList` has a single entry without a number, and `monthly`
/// lists have one entry per year holding its months. The shape of the entries tells which, so a new list type that
/// reuses one of these shapes still parses.
class ErrSeasonList {
  /// True when ERR gives the newest episode first, so the episodes must be reversed to read in order.
  final bool descending;
  final List<ErrSeasonEntry> entries;

  const ErrSeasonList({required this.descending, required this.entries});

  ErrSeasonEntry? entry(int key) {
    for (final entry in entries) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  /// The key of the season the page was opened on, from ERR's own `active` flags.
  static int? activeKey(Object? raw) {
    final items = raw is Map ? raw['items'] : null;
    if (items is! List) return null;
    for (final item in items.whereType<Map<String, dynamic>>()) {
      if (item['active'] == true || _anyActive(item['items'])) return (item['id'] as num?)?.toInt() ?? 1;
    }
    return null;
  }

  static bool _anyActive(Object? items) => items is List && items.any((i) => i is Map && i['active'] == true);
}

/// Null when the page has no usable season list, which is the case for a single film.
ErrSeasonList? errParseSeasonList(Object? raw) {
  final items = raw is Map ? raw['items'] : null;
  if (items is! List || items.isEmpty) return null;
  final entries = [for (final item in items.whereType<Map<String, dynamic>>()) ?_entry(item)];
  if (entries.isEmpty) return null;
  return ErrSeasonList(descending: (raw as Map)['contentOrder'] == 'desc', entries: entries);
}

ErrSeasonEntry? _entry(Map<String, dynamic> item) {
  final first = (item['firstContentId'] as num?)?.toInt();
  if (first == null) return null;
  final contents = item['contents'];
  final nested = item['items'];
  return ErrSeasonEntry(
    key: (item['id'] as num?)?.toInt() ?? 1,
    name: item['name'] as String?,
    firstContentId: first,
    contents: contents is List ? contents.whereType<Map<String, dynamic>>().toList() : null,
    months: nested is List ? [for (final month in nested.whereType<Map<String, dynamic>>()) ?_entry(month)] : const [],
  );
}
