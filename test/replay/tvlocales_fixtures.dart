import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_api.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/tvlocales';

String tvLocalesFixture(String name) => File('$_fixtures/$name').readAsStringSync();

/// A Freecaster video id and the embed document its player configuration is served from.
const tvLocalesVideos = {
  'a30728c1-5ff5-4435-a10b-0f0454743de2': 'freecaster_embed_telemb.json',
  'a30722b3-e0b3-4599-8e73-02bc4fad37df': 'freecaster_embed_tvlux_subtitled.json',
  '2e2f89f0-df74-343f-ac3d-88023b2fab46': 'freecaster_embed_tvlux_archive.json',
  '30000000-0000-0000-0000-000000000003': 'freecaster_embed_no_sources.json',
  '40000000-0000-0000-0000-000000000004': 'freecaster_embed_mp4_only.json',
};

/// An episode page that carries only a player for [videoId].
String tvLocalesPlayerPage(String videoId) =>
    '<html><body><div class="freecaster-player" data-video-id="$videoId"></div></body></html>';

/// What a fake station site and fake Freecaster answer, by request.
typedef TvLocalesRoute = http.Response? Function(http.Request request);

/// Requests a test made, in order, so that tests can check hosts, counts and headers.
class TvLocalesLog {
  final List<http.Request> requests = [];

  List<String> get paths => [for (final r in requests) r.url.path + (r.url.hasQuery ? '?${r.url.query}' : '')];
}

http.Response htmlResponse(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'text/html; charset=utf-8'});

http.Response jsonResponse(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});

/// An API over [route]; a request the route does not answer is a 404. Requests are not spaced out.
TvLocalesApi tvLocalesApi(TvLocalesRoute route, {TvLocalesLog? log}) {
  final client = MockClient((request) async {
    log?.requests.add(request);
    return route(request) ?? http.Response('not found', 404);
  });
  return TvLocalesApi(MediaServerHttpClient(client: client), minGap: Duration.zero);
}
