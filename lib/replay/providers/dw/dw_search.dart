import 'dw_numbering.dart';

/// The only fields of a search hit the app reads. Asking for them alone keeps a page of hits small.
const _resultFields = [
  'title',
  'shortTeaser',
  'teaser',
  'contentDate',
  'duration',
  'roadTeaserKicker',
  'mainContentImageLink.target.staticUrl',
  'unifiedPrograms.id',
  'unifiedPrograms.name',
];

/// The search engine returns at most this many hits for one query, however deep the page.
const dwSearchWindow = 10000;

Map<String, dynamic> _fields() => {
  for (final f in _resultFields) f: {'raw': <String, dynamic>{}},
};

String _utc(DateTime date) => date.toUtc().toIso8601String();

List<Map<String, dynamic>> _videoFilters({int? programme, int? year}) => [
  {'modelType': 'VIDEO'},
  if (programme != null) {'unifiedPrograms.id': programme},
  if (year != null)
    {
      'contentDate': {'from': _utc(dwYearStart(year)), 'to': _utc(dwYearStart(year + 1))},
    },
];

/// A page of videos, newest first, or best match first when [query] is given. [page] is one-based.
Map<String, dynamic> dwVideoQuery({String query = '', int? programme, int? year, int page = 1, int size = 20}) => {
  'query': query,
  'filters': {'all': _videoFilters(programme: programme, year: year)},
  if (query.isEmpty)
    'sort': [
      {'contentDate': 'desc'},
    ],
  'result_fields': _fields(),
  'page': {'size': size, 'current': page},
};

/// Asks how many videos a programme has in each year from [firstYear] to [lastYear], without returning any.
Map<String, dynamic> dwYearCountsQuery({required int programme, required int firstYear, required int lastYear}) => {
  'query': '',
  'filters': {'all': _videoFilters(programme: programme)},
  'facets': {
    'contentDate': [
      {
        'type': 'range',
        'ranges': [
          for (var y = firstYear; y <= lastYear; y++)
            {'from': _utc(dwYearStart(y)), 'to': _utc(dwYearStart(y + 1)), 'name': '$y'},
        ],
      },
    ],
  },
  'result_fields': {
    'title': {'raw': <String, dynamic>{}},
  },
  'page': {'size': 1, 'current': 1},
};

List<Map<String, dynamic>> dwHits(Map<String, dynamic> response) {
  final results = response['results'];
  return results is List ? results.whereType<Map<String, dynamic>>().toList() : const [];
}

int dwTotalHits(Map<String, dynamic> response) {
  final total = ((response['meta'] as Map?)?['page'] as Map?)?['total_results'];
  return total is num ? total.toInt().clamp(0, dwSearchWindow) : 0;
}

/// Videos per year from a [dwYearCountsQuery] answer, years without videos left out.
Map<int, int> dwYearCounts(Map<String, dynamic> response) {
  final groups = (response['facets'] as Map?)?['contentDate'];
  if (groups is! List || groups.isEmpty) return const {};
  final data = (groups.first as Map)['data'];
  final counts = <int, int>{};
  for (final bucket in (data is List ? data : const []).whereType<Map<String, dynamic>>()) {
    final year = int.tryParse('${bucket['name']}');
    final count = (bucket['count'] as num?)?.toInt() ?? 0;
    if (year != null && count > 0) counts[year] = count;
  }
  return counts;
}
