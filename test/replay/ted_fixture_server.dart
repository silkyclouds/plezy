import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/ted/ted_api.dart';
import 'package:plezy/replay/providers/ted/ted_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/ted';

String tedFixture(String name) => File('$_fixtures/$name').readAsStringSync();

const _json = {'content-type': 'application/json'};
const _playlist = {'content-type': 'application/vnd.apple.mpegurl'};
const _encryptedMaster =
    '#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://key"\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8\n';

/// Answers TED requests from recorded responses, by the text of the GraphQL query and by the path of HLS masters.
class TedFixtureServer {
  final List<String> queries = [];
  final List<Uri> fetched = [];

  http.Response handle(http.Request request) {
    if (request.url.host == 'www.ted.com') return _graphql(request);
    fetched.add(request.url);
    final project = RegExp(r'project_masters/(\d+)/').firstMatch(request.url.path)?.group(1);
    return switch (project) {
      '7506' => http.Response(tedFixture('master_many_subtitles.m3u8'), 200, headers: _playlist),
      '12091' => http.Response(tedFixture('master_plain.m3u8'), 200, headers: _playlist),
      '1001' => http.Response('', 404),
      '1002' => http.Response('', 403),
      '1003' => http.Response('', 500),
      '1004' => http.Response(_encryptedMaster, 200, headers: _playlist),
      '1005' => http.Response('<html>not a playlist</html>', 200, headers: _playlist),
      _ => http.Response('', 404),
    };
  }

  http.Response _graphql(http.Request request) {
    final query = (jsonDecode(request.body) as Map<String, dynamic>)['query'] as String;
    queries.add(query);
    if (query.contains('search(q: "429")')) return http.Response('slow down', 429, headers: {'retry-after': '30'});
    if (query.contains('search(q: "broken")')) {
      return _ok({
        'errors': [
          {'message': 'Something broke'},
        ],
      });
    }
    final name = _fixtureFor(query);
    if (name != null) return http.Response(tedFixture(name), 200, headers: _json);
    return _ok(_synthetic(query));
  }

  String? _fixtureFor(String query) {
    final routes = <String, String>{
      'topic(slug: "science")': 'topic_science.json',
      'playlists(first: 20)': 'playlists.json',
      'playlist(slug: "talks_on_ai_and_the_future_of_work")': 'playlist_ai.json',
      'search(q: "climate")': 'search_climate.json',
      'search(q: "zzzz")': 'search_empty.json',
      't0: video(': 'videos_by_slug_climate.json',
      'video(slug: "candace_parker_how_to_break_down_barriers_and_not_accept_limits")': 'video_candace_parker.json',
      'video(slug: "nope_not_a_talk")': 'video_missing.json',
      'videos(first: 20, language: "fr")': 'videos_french.json',
      'videos(first: 20, after: "20")': 'videos_page2.json',
      'videos(first: 20)': 'videos_latest.json',
    };
    for (final entry in routes.entries) {
      if (query.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Responses for cases no recording exists for: talks without a stream, removed masters, a playlist of 120 talks.
  Map<String, dynamic> _synthetic(String query) {
    final talk = RegExp(r'video\(slug: "(\w+)"\)').firstMatch(query)?.group(1);
    if (talk != null) {
      return {
        'data': {'video': _talk(talk, hls: _hlsFor(talk))},
      };
    }
    if (query.contains('playlist(slug: "long_playlist")')) return _longPlaylist(query);
    if (query.contains('playlist(slug:')) {
      return {
        'data': {'playlist': null},
      };
    }
    return {'data': {}};
  }

  String? _hlsFor(String slug) => switch (slug) {
    'no_stream' => null,
    'removed_master' => 'https://hls.ted.com/project_masters/1001/manifest.m3u8',
    'forbidden_master' => 'https://hls.ted.com/project_masters/1002/manifest.m3u8',
    'failing_master' => 'https://hls.ted.com/project_masters/1003/manifest.m3u8',
    'encrypted_master' => 'https://hls.ted.com/project_masters/1004/manifest.m3u8',
    'html_master' => 'https://hls.ted.com/project_masters/1005/manifest.m3u8',
    _ => 'https://hls.ted.com/project_masters/12091/manifest.m3u8',
  };

  Map<String, dynamic> _talk(String slug, {String? hls}) => {
    'id': slug.hashCode.toString(),
    'title': slug,
    'slug': slug,
    'hlsUrl': hls,
  };

  Map<String, dynamic> _longPlaylist(String query) {
    final after = int.tryParse(RegExp(r'after: "(\d+)"').firstMatch(query)?.group(1) ?? '') ?? 0;
    final nodes = [for (var i = after; i < after + 50 && i < 120; i++) _talk('talk_$i', hls: 'https://x/$i')];
    return {
      'data': {
        'playlist': {
          'id': '1',
          'title': 'A long playlist',
          'slug': 'long_playlist',
          'videos': {'totalCount': 120, 'nodes': nodes},
        },
      },
    };
  }

  http.Response _ok(Map<String, dynamic> body) => http.Response(jsonEncode(body), 200, headers: _json);

  MediaServerHttpClient get client => MediaServerHttpClient(client: MockClient((r) async => handle(r)));

  TedProvider provider({String? language}) => TedProvider.withApi(TedApi(client), language: language);
}
