import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_api.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_json.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_provider.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_rails.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Talks to the real ARD Mediathek. Run with `PLEZY_LIVE_TESTS=1 flutter test test/replay/ardmediathek_live_test.dart`.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';
  const skip = 'set PLEZY_LIVE_TESTS=1 to reach the network';

  test('the gateway serves a series down to a playable or refused stream', () async {
    final http = MediaServerHttpClient();
    final provider = ArdMediathekProvider(http);

    final rails = await provider.home();
    expect(rails, isNotEmpty);
    expect(rails.every((r) => r.titles.isNotEmpty), isTrue);

    final hits = await provider.search('watzmann ermittelt');
    final show = hits.firstWhere((t) => t.kind == ReplayKind.show && t.title == 'Watzmann ermittelt');
    final seasons = await provider.children(show.ref);
    expect(seasons.length, greaterThan(1));
    final episodes = await provider.children(seasons.first.ref);
    expect(episodes, isNotEmpty);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.seasonNumber, 1);

    final verdicts = await provider.predictAvailability(episodes.take(8).toList(), 'BE');
    final playback = await provider.playback(episodes.first.ref);
    final expected = verdicts[episodes.first.ref];
    if (playback.isPlayable) {
      expect(expected, isNot(ReplayAvailability.geoBlocked));
      final response = await http.get(playback.streams.first.url.toString());
      expect(response.statusCode, 200);
      expect(response.data.toString(), startsWith('#EXTM3U'));
    } else {
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(expected, ReplayAvailability.geoBlocked);
    }
  }, skip: live ? false : skip);

  test('the whole catalogue and a row page through their listings', () async {
    final http = MediaServerHttpClient();
    final provider = ArdMediathekProvider(http);
    final everything = await provider.listing(replayAllBrowseId, page: 1);
    expect(everything.totalCount, greaterThan(1000));
    expect(everything.titles, isNotEmpty);

    final home = await ArdMediathekApi(http).home();
    final row = ardMaps(home['widgets']).firstWhere((w) => w['type'] == 'gridlist' && ardBrowseId(w) != null);
    final page = await provider.listing(ardBrowseId(row)!);
    expect(page.titles, isNotEmpty);
    expect(await provider.category('kanal/phoenix'), isNotEmpty);
  }, skip: live ? false : skip);

  test('a sample across categories plays or is predicted as blocked', () async {
    final provider = ArdMediathekProvider(MediaServerHttpClient());
    final videos = <ReplayRef, ReplayTitle>{};
    for (final source in ['home', 'rubrik/serien', 'rubrik/dokus', 'rubrik/kinderfamilie', 'rubrik/tagesschau']) {
      final rails = source == 'home' ? await provider.home() : await provider.category(source);
      final perSource = [
        for (final rail in rails)
          for (final title in rail.titles.where((t) => t.isPlayable && t.kind != ReplayKind.clip).take(2)) title,
      ];
      for (final video in perSource.take(8)) {
        videos[video.ref] = video;
      }
    }
    expect(videos, isNotEmpty);

    final verdicts = await provider.predictAvailability(videos.values.toList(), 'BE');
    final reasons = <ReplayAvailability, int>{};
    var played = 0;
    for (final video in videos.values) {
      final playback = await provider.playback(video.ref);
      if (playback.isPlayable) {
        played++;
        final predicted = verdicts[video.ref];
        if (predicted != null && predicted != ReplayAvailability.playable) {
          // ignore: avoid_print
          print('ardmediathek predicted $predicted but plays: ${video.title} ${playback.streams.first.url}');
        }
      } else {
        reasons.update(playback.availability, (n) => n + 1, ifAbsent: () => 1);
        final predicted = verdicts[video.ref];
        if (predicted != null) expect(predicted, isNot(ReplayAvailability.playable), reason: video.title);
      }
    }
    final predictedBlocked = verdicts.values.where((v) => v != ReplayAvailability.playable).length;
    // ignore: avoid_print
    print(
      'ardmediathek sample of ${videos.length}: $played play, not playable $reasons, predicted blocked $predictedBlocked',
    );
    final unjudged = [
      for (final v in videos.values)
        if (!verdicts.containsKey(v.ref)) '${v.title} ${v.ref}',
    ];
    // ignore: avoid_print
    print('ardmediathek not judged: $unjudged');
  }, skip: live ? false : skip);
}
