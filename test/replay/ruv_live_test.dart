import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/ruv/ruv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real RÚV catalogue. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/ruv_live_test.dart`.
/// The Iceland-only checks assume the machine is outside Iceland.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('a worldwide programme goes down to a playable HLS master', () async {
    final http = MediaServerHttpClient();
    final provider = RuvProvider(http);
    expect(await provider.categories(), hasLength(greaterThan(10)));

    final hits = await provider.search('Kastljós');
    final show = hits.firstWhere((t) => t.title == 'Kastljós' && t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, hasLength(1));
    final episodes = await provider.children(seasons.single.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.last.episodeNumber, greaterThanOrEqualTo(episodes.first.episodeNumber!));

    final playback = await provider.playback(episodes.last.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await http.get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('Icelandic text is searchable and artwork resizes', () async {
    final http = MediaServerHttpClient();
    final provider = RuvProvider(http);
    final hits = await provider.search('náttúra');
    expect(hits, isNotEmpty);

    final poster = hits.firstWhere((t) => t.posterUrl != null).posterUrl!;
    final response = await http.get(provider.imageUrl(poster, width: 300, height: 450));
    expect(response.statusCode, 200);
  }, skip: live ? false : skip);

  test('home titles are flagged and Iceland-only ones refuse to play abroad', () async {
    final provider = RuvProvider(MediaServerHttpClient());
    final rails = await provider.home();
    expect(rails, isNotEmpty);
    final titles = [for (final rail in rails) ...rail.titles];

    final verdicts = await provider.predictAvailability(titles, 'BE');
    final blocked = titles.where((t) => verdicts[t.ref] == ReplayAvailability.geoBlocked).toList();
    final open = titles.where((t) => verdicts[t.ref] == ReplayAvailability.playable).toList();
    expect(blocked, isNotEmpty);
    expect(open, isNotEmpty);

    final inIceland = await provider.predictAvailability(titles, 'IS');
    expect(inIceland.values.toSet(), {ReplayAvailability.playable});

    final ref = blocked.first.kind == ReplayKind.movie
        ? blocked.first.ref
        : (await provider.children((await provider.children(blocked.first.ref)).single.ref)).first.ref;
    final playback = await provider.playback(ref);
    expect(playback.availability, ReplayAvailability.geoBlocked);
  }, skip: live ? false : skip);

  test('a film plays through its programme ref', () async {
    final provider = RuvProvider(MediaServerHttpClient());
    final rails = await provider.category('kvikmyndir');
    final titles = [for (final rail in rails) ...rail.titles];
    final verdicts = await provider.predictAvailability(titles, 'BE');
    final film = titles.firstWhere((t) => t.kind == ReplayKind.movie && verdicts[t.ref] == ReplayAvailability.playable);
    final playback = await provider.playback(film.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
  }, skip: live ? false : skip);
}
