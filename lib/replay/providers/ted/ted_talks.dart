import '../../model/replay_title.dart';
import 'ted_api.dart';
import 'ted_mapper.dart';
import 'ted_queries.dart';

/// Talks per page of every list; the endpoint takes any size, this keeps responses small.
const tedPageSize = 20;

/// Standalone talks: the latest list, topic lists, single talks and search.
class TedTalks {
  final TedApi _api;
  final String? _language;

  /// [language] is an ISO 639-1 code; talks translated into it come back with a title in it. English is the
  /// original language of nearly every talk, so it needs no filter.
  TedTalks(this._api, {String? language}) : _language = language == null || language == 'en' ? null : language;

  Future<ReplayPage> latest({int page = 0}) async {
    final data = await _api.query(tedVideosQuery(first: tedPageSize, after: page * tedPageSize, language: _language));
    return _page(data['videos']);
  }

  Future<ReplayPage> topic(String slug, {int page = 0}) async {
    final data = await _api.query(tedTopicQuery(slug, first: tedPageSize, after: page * tedPageSize));
    return _page((data['topic'] as Map<String, dynamic>?)?['videos']);
  }

  /// The raw `Video` node, or null when TED no longer has the talk.
  Future<Map<String, dynamic>?> node(String slug) async {
    final data = await _api.query(tedVideoQuery(slug));
    final node = data['video'];
    return node is Map<String, dynamic> ? node : null;
  }

  Future<ReplayTitle?> talk(String slug) async {
    final node = await this.node(slug);
    return node == null ? null : tedTalkFromNode(node);
  }

  /// Talks matching [query], best match first. The search returns slugs only, so they are loaded in one request.
  Future<List<ReplayTitle>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final found = await _api.query(tedSearchQuery(text));
    final results = (found['search'] as Map<String, dynamic>?)?['results'];
    if (results is! List) return const [];
    final slugs = <String>{
      for (final result in results.whereType<Map<String, dynamic>>())
        if (result['slug'] is String) result['slug'] as String,
    }.take(tedPageSize).toList();
    if (slugs.isEmpty) return const [];

    final loaded = await _api.query(tedVideosBySlugQuery(slugs));
    return [for (var i = 0; i < slugs.length; i++) ?_talkAt(loaded['t$i'])];
  }

  ReplayTitle? _talkAt(Object? node) => node is Map<String, dynamic> ? tedTalkFromNode(node) : null;

  ReplayPage _page(Object? connection) =>
      ReplayPage(titles: tedTalksFromConnection(connection), totalCount: tedTotalCount(connection));
}
