import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_api.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/stvplayer';

/// The moment every test runs at, so availability windows in the recordings stay valid.
final stvNow = DateTime.utc(2026, 10, 22, 9);

Map<String, dynamic> stvFixture(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

ReplayRef stvRef(String nativeId) => ReplayRef('stvplayer', nativeId);

/// A provider answering from the recordings, and every request it made.
class StvHarness {
  final StvPlayerProvider provider;
  final List<http.Request> requests;

  StvHarness(this.provider, this.requests);
}

StvHarness stvHarness() {
  final requests = <http.Request>[];
  final routes = _Routes();
  final client = MediaServerHttpClient(
    client: MockClient((request) async {
      requests.add(request);
      return routes.answer(request);
    }),
  );
  final api = StvPlayerApi(client, now: () => stvNow);
  return StvHarness(StvPlayerProvider.withApi(api, client, clock: () => stvNow), requests);
}

/// Episode ids that exist only in the tests: the Scotland Tonight recording with one field changed.
const stvExpiredEpisode = '900001';
const stvUpcomingEpisode = '900002';
const stvAccountEpisode = '900003';
const stvProtectedEpisode = '900004';
const stvNoVideoEpisode = '900005';
const stvNoSubtitlesEpisode = '900006';

class _Routes {
  final Map<String, Map<String, dynamic>> _episodes = {};

  _Routes() {
    for (final name in [
      'episode_detail',
      'episodes_by_programme',
      'episodes_by_series',
      'episodes_recent',
      'episodes_flat_scotland_tonight',
      'episodes_beat_the_bridge_season2',
    ]) {
      final body = stvFixture(name)['results'];
      for (final e in body is List ? body : [body]) {
        _episodes['${e['id']}'] = e as Map<String, dynamic>;
      }
    }
    _addVariants();
  }

  void _addVariants() {
    final base = _episodes['235340']!;
    Map<String, dynamic> variant(String id, void Function(Map<String, dynamic>) edit) {
      final copy = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      copy['id'] = id;
      edit(copy);
      return _episodes[id] = copy;
    }

    variant(stvExpiredEpisode, (e) => e['availability'] = {'from': null, 'until': '2026-10-01T23:59:00+0000'});
    variant(stvUpcomingEpisode, (e) => e['availability'] = {'from': '2026-12-01T00:00:00+0000', 'until': null});
    variant(stvAccountEpisode, (e) => e['vipExclusive'] = true);
    variant(stvProtectedEpisode, (e) => (e['programme'] as Map<String, dynamic>)['drmEnabled'] = true);
    variant(
      stvNoVideoEpisode,
      (e) => e
        ..['video'] = null
        ..['standardVideo'] = null,
    );
    variant(stvNoSubtitlesEpisode, (e) => e['_subtitles'] = null);
  }

  http.Response answer(http.Request request) {
    final path = request.url.path;
    final query = request.url.queryParameters;
    if (request.url.host == 'edge.api.brightcove.com') return _brightcove(path.substring(path.lastIndexOf('/') + 1));

    final segments = path.replaceFirst('/v1/', '').split('/');
    return switch (segments) {
      ['categories'] => _json(stvFixture('categories')),
      ['programmes'] => _json(_programmes(query)),
      ['programmes', final guid] => _programme(guid),
      ['episodes'] => _json(_episodeList(query)),
      ['episodes', final id] => _episodes[id] == null ? _missing() : _json({'success': true, 'results': _episodes[id]}),
      ['shortform'] => _json(stvFixture('clips')),
      ['shortform', _] => _json(stvFixture('clip_detail')),
      _ => _missing(),
    };
  }

  Map<String, dynamic> _programmes(Map<String, String> query) {
    if (query['category'] == 'dramas' && query['orderBy'] == 'name') return stvFixture('category_programmes');
    final all = stvFixture('programmes');
    return (int.tryParse(query['offset'] ?? '0') ?? 0) > 0 ? {...all, 'results': []} : all;
  }

  http.Response _programme(String guid) {
    final fixture = switch (guid) {
      'chase-celebrity' => 'programme_detail',
      'taggart' => 'programme_taggart',
      'stv-beat-the-bridge' => 'programme_beat_the_bridge',
      'scotland-tonight' => 'programme_scotland_tonight',
      _ => null,
    };
    return fixture == null ? _missing() : _json(stvFixture(fixture));
  }

  Map<String, dynamic> _episodeList(Map<String, String> query) {
    final fixture = switch ((query['programme.guid'], query['playerSeries.guid'])) {
      ('taggart', 'taggart-series-1') => 'episodes_by_series',
      ('taggart', null) => 'episodes_by_programme',
      ('scotland-tonight', null) => 'episodes_flat_scotland_tonight',
      ('stv-beat-the-bridge', 'stv-beat-the-bridge-episodes-26-50') => 'episodes_beat_the_bridge_season2',
      (null, _) => 'episodes_recent',
      _ => null,
    };
    return fixture == null ? {'success': true, 'totalResults': 0, 'results': []} : stvFixture(fixture);
  }

  http.Response _brightcove(String videoId) {
    return switch (videoId) {
      '6407203218112' || '6407195108112' => _file('synthetic_brightcove_clear'),
      '6184438149001' => _file('synthetic_brightcove_drm'),
      '6183018745001' => _file('brightcove_geoblocked_BE', status: 403),
      '6405447349112' => _file('synthetic_brightcove_not_found', status: 404),
      '6405508853112' => _file('synthetic_brightcove_unauthorized', status: 401),
      '6405758720112' => _file('synthetic_brightcove_http_only'),
      '6393078069112' => _file('synthetic_brightcove_dash_only'),
      _ => _file('synthetic_brightcove_not_found', status: 404),
    };
  }

  http.Response _file(String name, {int status = 200}) =>
      http.Response(File('$_fixtures/$name.json').readAsStringSync(), status, headers: _jsonHeaders);

  http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

  http.Response _missing() => http.Response(
    '{"success":false,"reason":{"code":14,"message":"Resource not found"}}',
    404,
    headers: _jsonHeaders,
  );
}

const _jsonHeaders = {'content-type': 'application/json'};
