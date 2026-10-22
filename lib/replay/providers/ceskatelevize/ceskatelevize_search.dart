import '../../model/replay_title.dart';
import 'ceskatelevize_api.dart';
import 'ceskatelevize_mapper.dart';
import 'ceskatelevize_queries.dart';

/// Search over shows and episodes. The server refuses keywords shorter than three characters.
class CeskaTelevizeSearch {
  static const _minLength = 3;
  static const _shows = 30;
  static const _episodes = 30;

  final CeskaTelevizeApi _api;
  final CeskaTelevizeMapper _mapper;

  CeskaTelevizeSearch(this._api, this._mapper);

  /// Shows first, then episodes. A film also answers as an episode named like itself; that duplicate is dropped.
  Future<List<ReplayTitle>> run(String query) async {
    final keyword = query.trim();
    if (keyword.length < _minLength) return const [];
    final answers = await Future.wait([
      _items(ceskatelevizeSearchShowsQuery, 'searchShows', keyword, _shows),
      _items(ceskatelevizeSearchEpisodesQuery, 'searchEpisodes', keyword, _episodes),
    ]);

    final shows = [for (final item in answers[0]) _mapper.programme(item)].nonNulls.toList();
    final filmSidps = {
      for (final item in answers[0])
        if ((item['programme'] as Map?)?['showType'] == 'movie') item['sidp'],
    };
    final episodes = [
      for (final item in answers[1])
        if (!(filmSidps.contains(item['sidp']) && item['title'] == item['showTitle'])) _mapper.episode(item),
    ].nonNulls;

    final seen = <String>{};
    return [
      for (final title in [...shows, ...episodes])
        if (seen.add(title.ref.toString())) title,
    ];
  }

  Future<List<Map<String, dynamic>>> _items(String document, String field, String keyword, int limit) async {
    final data = await _api.query(
      document,
      variables: {'limit': limit, 'offset': 0, 'search': keyword, 'onlyPlayable': true},
      ttl: CeskaTelevizeApi.detailsTtl,
    );
    final items = (data[field] as Map?)?['items'];
    return items is List ? items.whereType<Map<String, dynamic>>().toList() : const [];
  }
}
