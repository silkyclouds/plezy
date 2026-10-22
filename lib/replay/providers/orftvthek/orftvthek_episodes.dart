import 'dart:async';
import 'dart:collection';

import 'orftvthek_api.dart';
import 'orftvthek_json.dart';

const _keptFields = [
  'id',
  'title',
  'sub_headline',
  'profile_title',
  'description',
  'teaser_text',
  'date',
  'livedate',
  'killdate',
  'duration_seconds',
  'right',
  'is_drm_protected',
  'has_active_youth_protection',
  'genre_id',
  'genre_title',
  'production_year',
  'age_classification',
  'video_type',
];
const _imageKeys = ['image', 'image16x9_with_logo', 'image2x3_with_logo', 'image2x3'];

/// Every episode of one show, read page by page and kept for a few minutes.
///
/// The API embeds each episode's chapters, stream list and tracking data, so a page is hundreds of kilobytes. Only
/// the fields the mapper reads are kept, which makes a long-running show cheap to hold. Sign-language versions are
/// dropped: they are separate programmes that repeat the plain one.
class OrfEpisodeLoader {
  static const _lifetime = Duration(minutes: 10);
  static const _pageSize = 50;
  static const _maxPages = 6;
  static const _maxShows = 12;

  final OrfApi _api;
  final DateTime Function() _now;
  final LinkedHashMap<int, ({DateTime at, Future<List<Map<String, dynamic>>> episodes})> _cache = LinkedHashMap();

  OrfEpisodeLoader(this._api, this._now);

  Future<List<Map<String, dynamic>>> all(int profileId) {
    final cached = _cache.remove(profileId);
    if (cached != null && _now().difference(cached.at) < _lifetime) {
      _cache[profileId] = cached;
      return cached.episodes;
    }
    final loading = _load(profileId);
    _cache[profileId] = (at: _now(), episodes: loading);
    if (_cache.length > _maxShows) _cache.remove(_cache.keys.first);
    unawaited(
      loading.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_cache[profileId]?.episodes, loading)) _cache.remove(profileId);
        },
      ),
    );
    return loading;
  }

  Future<List<Map<String, dynamic>>> _load(int profileId) async {
    final first = await _api.profileEpisodes(profileId, limit: _pageSize);
    final pages = (orfInt(first['pages']) ?? 1).clamp(1, _maxPages);
    final rest = await Future.wait([
      for (var page = 2; page <= pages; page++) _api.profileEpisodes(profileId, page: page, limit: _pageSize),
    ]);
    final seen = <int>{};
    return [
      for (final page in [first, ...rest])
        for (final item in orfItems(page))
          if (item['is_oegs'] != true && seen.add(orfInt(item['id']) ?? -1)) _slim(item),
    ];
  }

  Map<String, dynamic> _slim(Map<String, dynamic> item) {
    final embedded = orfMap(item['_embedded']);
    final profileLink = orfMap(item['_links'])?['profile'];
    return {
      for (final field in _keptFields)
        if (item[field] != null) field: item[field],
      if (profileLink != null) '_links': {'profile': profileLink},
      if (embedded != null)
        '_embedded': {
          for (final key in _imageKeys)
            if (embedded[key] != null) key: embedded[key],
        },
    };
  }
}
