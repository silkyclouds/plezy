import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/err/err_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real ERR Jupiter services. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/err_live_test.dart`.
/// The Estonia-only checks assume the machine is outside Estonia.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('a worldwide programme goes down to a playable HLS master', () async {
    final http = MediaServerHttpClient();
    final provider = ErrProvider(http);
    expect(await provider.home(), isNotEmpty);

    final hits = await provider.search('Siin ja praegu');
    final show = hits.firstWhere((t) => t.title == 'Siin ja praegu' && t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    expect(seasons.first.seasonNumber, 1);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.showRef, show.ref);

    final playback = await provider.playback(episodes.first.ref);
    expect(playback.isPlayable, isTrue, reason: playback.message);
    final response = await http.get(playback.streams.first.url.toString());
    expect(response.statusCode, 200);
    expect(response.data.toString(), startsWith('#EXTM3U'));
  }, skip: live ? false : skip);

  test('a programme filed by month lists its years and their episodes', () async {
    final provider = ErrProvider(MediaServerHttpClient());
    final show = (await provider.search('Terevisioon')).firstWhere((t) => t.title == 'Terevisioon');
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(3));
    expect(seasons.last.seasonNumber, greaterThanOrEqualTo(2026));
    final episodes = await provider.children(seasons.last.ref);
    expect(episodes, isNotEmpty);
    final numbers = episodes.map((e) => e.episodeNumber!).toList();
    expect(numbers, [...numbers]..sort());
  }, skip: live ? false : skip);

  test('artwork resolves to a picture', () async {
    final http = MediaServerHttpClient();
    final provider = ErrProvider(http);
    final film = (await provider.home()).expand((r) => r.titles).firstWhere((t) => t.posterUrl != null);
    expect(provider.ownsImage(film.posterUrl!), isTrue);
    final response = await http.get(provider.imageUrl(film.posterUrl!, width: 300));
    expect(response.statusCode, 200);
  }, skip: live ? false : skip);

  test('forecast and playback agree on a sample of the catalogue', () async {
    final provider = ErrProvider(MediaServerHttpClient());
    final page = await provider.listing(replayAllBrowseId, page: 5);
    expect(page.totalCount, greaterThan(2000));
    final playable = page.titles.where((t) => t.isPlayable).take(20).toList();
    expect(playable, isNotEmpty);

    final forecast = await provider.predictAvailability(playable, 'BE');
    final tally = <ReplayAvailability, int>{};
    for (final title in playable) {
      final playback = await provider.playback(title.ref);
      tally[playback.availability] = (tally[playback.availability] ?? 0) + 1;
      final predicted = forecast[title.ref] ?? ReplayAvailability.playable;
      expect(playback.availability, predicted, reason: '${title.ref} ${title.title}');
    }
    // ignore: avoid_print
    print('ERR sample of ${playable.length}: $tally');
    expect(tally[ReplayAvailability.playable], greaterThan(0));
  }, skip: live ? false : skip);
}
