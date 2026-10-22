import 'dart:convert';

const _talkFields =
    'id title slug description presenterDisplayName duration hlsUrl publishedAt recordedOn '
    'topics { nodes { slug } } primaryImageSet { url aspectRatioName }';
const _playlistFields = 'id title slug description primaryImageSet { url aspectRatioName }';

/// A GraphQL string literal. JSON string syntax is a subset of GraphQL's.
String _text(String value) => jsonEncode(value);

/// Cursors on this endpoint behave as plain offsets, so `after` is the number of talks to skip.
String _paging(int first, int after) => 'first: $first${after > 0 ? ', after: ${_text('$after')}' : ''}';

String tedVideosQuery({required int first, int after = 0, String? language}) {
  final lang = language == null ? '' : ', language: ${_text(language)}';
  return '{ videos(${_paging(first, after)}$lang) { totalCount nodes { $_talkFields } } }';
}

String tedTopicQuery(String slug, {required int first, int after = 0}) =>
    '{ topic(slug: ${_text(slug)}) { videos(${_paging(first, after)}) { totalCount nodes { $_talkFields } } } }';

String tedPlaylistsQuery({required int first, int after = 0}) =>
    '{ playlists(${_paging(first, after)}) { totalCount nodes { $_playlistFields } } }';

String tedPlaylistQuery(String slug, {required int first, int after = 0}) =>
    '{ playlist(slug: ${_text(slug)}) { $_playlistFields '
    'videos(${_paging(first, after)}) { totalCount nodes { $_talkFields } } } }';

String tedVideoQuery(String slug) => '{ video(slug: ${_text(slug)}) { $_talkFields } }';

/// Several talks in one request, answered as `t0`, `t1`, ... in the order given.
String tedVideosBySlugQuery(List<String> slugs) =>
    '{ ${[for (final (i, slug) in slugs.indexed) 't$i: video(slug: ${_text(slug)}) { $_talkFields }'].join(' ')} }';

String tedSearchQuery(String text) => '{ search(q: ${_text(text)}) { results { ... on SearchTalk { slug } } } }';
