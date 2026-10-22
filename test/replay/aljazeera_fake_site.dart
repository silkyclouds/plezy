import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_api.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/aljazeera';

/// Id of the video whose recorded Brightcove record is served by default.
const recordedVideo = '6407140246112';

const rotatedKey = 'BCpkRotatedKeyForTests';

Map<String, dynamic> aljazeeraFixture(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> recordedPosts(String name) =>
    ((aljazeeraFixture(name)['data'] as Map)['articles'] as List).cast<Map<String, dynamic>>();

/// One episode post shaped like the recorded ones, with the given identity and an optional Brightcove video.
Map<String, dynamic> episodePost(String slug, int number, DateTime date, {bool withVideo = true}) {
  final post = jsonDecode(jsonEncode(recordedPosts('section_posts_inside_story').first)) as Map<String, dynamic>;
  post['id'] = '$number';
  post['title'] = 'Episode $number of $slug';
  post['date'] = date.toUtc().toIso8601String().substring(0, 19);
  post['video'] = {'id': withVideo ? '9$number' : '', 'duration': '24:00'};
  post['programs'] = [
    {'id': '1', 'name': slug, 'slug': slug},
  ];
  return post;
}

/// [count] posts of [slug], newest first, [days] apart, the newest on [newest].
List<Map<String, dynamic>> postHistory(String slug, DateTime newest, int count, {int days = 1}) => [
  for (var i = 0; i < count; i++) episodePost(slug, count - i, newest.subtract(Duration(days: i * days))),
];

/// Serves recorded Al Jazeera responses, plus generated post histories for programmes that need many pages.
class FakeAljazeera {
  /// Posts by programme slug, newest first. A slug that is absent answers like a programme that does not exist.
  final Map<String, List<Map<String, dynamic>>> posts = {
    'inside-story': recordedPosts('section_posts_inside_story'),
    'newsfeed': recordedPosts('section_posts_newsfeed_clips'),
    'witness': recordedPosts('section_posts_witness_youtube_only'),
  };

  /// Brightcove answers by video id: status and body.
  final Map<String, (int, Object)> videos = {recordedVideo: (200, aljazeeraFixture('brightcove_playback'))};

  /// The key Brightcove accepts, and the key the player script advertises.
  String acceptedKey = AljazeeraApi.defaultPolicyKey;
  String scriptKey = rotatedKey;

  /// Programmes appended to a section's recorded list, by section.
  final Map<String, List<Object?>> extraProgrammes = {};

  int status = 200;
  Map<String, String> statusHeaders = const {};
  final List<http.Request> requests = [];

  Iterable<Uri> get graphql => requests.map((r) => r.url).where((u) => u.path == '/graphql');

  int get postRequests =>
      graphql.where((u) => u.queryParameters['operationName'] == 'ArchipelagoSectionPostsQuery').length;

  http.Response handle(http.Request request) {
    requests.add(request);
    if (status != 200) return http.Response('{}', status, headers: statusHeaders);
    final url = request.url;
    if (url.host == 'www.aljazeera.com' && url.path == '/graphql') return _graphql(request);
    if (url.host == 'edge.api.brightcove.com') return _video(request);
    if (url.host == 'players.brightcove.net') {
      return http.Response('var o={videoCloud:{policyKey:"$scriptKey",video:null}};', 200);
    }
    return http.Response('{}', 404);
  }

  http.Response _graphql(http.Request request) {
    final query = request.url.queryParameters;
    if (request.headers['wp-site'] != 'aje' || query['wp-site'] != 'aje') return http.Response('{}', 400);
    final variables = jsonDecode(query['variables']!) as Map<String, dynamic>;
    return switch (query['operationName']) {
      'ArchipelagoProgramsQuery' => _programmes(variables),
      'ArchipelagoSectionPostsQuery' => _posts(variables),
      _ => _json({'errors': <Object>[]}),
    };
  }

  http.Response _programmes(Map<String, dynamic> variables) {
    final name = variables['category'] == 'tv-shows' ? 'programs_tv_shows' : 'programs_documentary';
    if (variables['offset'] != 0) return _noPosts('programs');
    final body = aljazeeraFixture(name);
    final list = (body['data'] as Map)['programs'] as List;
    list.addAll(extraProgrammes[variables['category']] ?? const []);
    return _json(body);
  }

  http.Response _posts(Map<String, dynamic> variables) {
    final all = posts[variables['category']] ?? const [];
    final offset = variables['offset'] as int;
    final quantity = variables['quantity'] as int;
    if (offset >= all.length) return _noPosts('articles');
    final end = offset + quantity < all.length ? offset + quantity : all.length;
    return _json({
      'data': {'articles': all.sublist(offset, end)},
    });
  }

  http.Response _video(http.Request request) {
    final key = (request.headers['Accept'] ?? '').split('pk=').last;
    if (key != acceptedKey) {
      return _json([
        {'error_code': 'INVALID_POLICY_KEY', 'message': 'Request policy key is missing or invalid.'},
      ], 401);
    }
    final reply =
        videos[request.url.pathSegments.last] ??
        (
          404,
          [
            {'error_code': 'VIDEO_NOT_FOUND', 'message': 'The designated resource was not found.'},
          ],
        );
    return _json(reply.$2, reply.$1);
  }

  http.Response _noPosts(String field) => _json({
    'errors': [
      {'message': 'no_posts_found', 'extensions': <String, Object>{}},
    ],
    'data': {field: null},
  });

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
}

AljazeeraApi apiOver(FakeAljazeera site, {DateTime Function()? clock}) => AljazeeraApi(
  MediaServerHttpClient(client: MockClient((r) async => site.handle(r))),
  minGap: Duration.zero,
  clock: clock,
);

AljazeeraProvider providerOver(FakeAljazeera site, {DateTime Function()? clock}) =>
    AljazeeraProvider.withApi(apiOver(site, clock: clock), clock: clock);
