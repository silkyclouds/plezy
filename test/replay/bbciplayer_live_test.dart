import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/bbciplayer/bbciplayer_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real iPlayer API. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/bbciplayer_live_test.dart`.
/// Outside the UK the last step ends in a geolocation answer, which is the expected result there.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('the catalogue serves a show down to a playback answer', () async {
    final provider = BbcIplayerProvider(MediaServerHttpClient());

    final rails = await provider.home();
    expect(rails, isNotEmpty);
    expect(await provider.categories(), isNotEmpty);

    final all = await provider.listing(replayAllBrowseId);
    expect(all.totalCount, greaterThan(1000));
    expect(all.titles, hasLength(provider.source.listingPageSize));

    final hits = await provider.search('strictly come dancing');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show);
    final seasons = await provider.children(show.ref);
    expect(seasons, isNotEmpty);
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, isNotNull);

    final playback = await provider.playback(episodes.first.ref);
    final reason = playback.message ?? playback.availability.name;
    expect(playback.isPlayable || playback.availability == ReplayAvailability.geoBlocked, isTrue, reason: reason);
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
