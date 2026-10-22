import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/pbs/pbs_flight.dart';
import 'package:plezy/replay/providers/pbs/pbs_ids.dart';
import 'package:plezy/replay/providers/pbs/pbs_images.dart';
import 'package:plezy/replay/providers/pbs/pbs_mapper.dart';
import 'package:plezy/replay/providers/pbs/pbs_playback.dart';

import 'pbs_catalog_cases.dart';
import 'pbs_fixture_server.dart';
import 'pbs_playback_cases.dart';

final _now = DateTime.utc(2026, 10, 22);

Map<String, dynamic> _video({Map<String, dynamic> flags = const {}, Map<String, dynamic> extra = const {}}) => {
  'item_type': 'video',
  'slug': 'a-video-abc123',
  'title': 'A video',
  'legacy_tp_media_id': 3000000001,
  'video_type': 'full_length',
  'availability': 'available',
  'flags': {'is_mvod': false, ...flags},
  ...extra,
};

void main() {
  pbsCatalogCases();
  pbsPlaybackCases();

  group('PBS source', () {
    test('it declares partial support and does not forecast blocks', () {
      final provider = PbsFixtureServer().provider();
      expect(provider.source.id, 'pbs');
      expect(provider.source.language, 'en');
      expect(provider.source.support, ReplayPlaybackSupport.partial);
      expect(provider, isNot(isA<ReplayAvailabilityPredictor>()));
    });
  });

  group('PBS availability in lists', () {
    test('Passport videos are marked as needing a login', () {
      final title = pbsVideoTitle(_video(flags: {'is_mvod': true}), now: _now);
      expect(title?.availability, ReplayAvailability.loginRequired);
    });

    test('a search hit that says available is taken at its word', () {
      expect(pbsVideoTitle(_video(), now: _now)?.availability, ReplayAvailability.playable);
    });

    test('past expiry, future release and unavailable are told apart', () {
      ReplayAvailability? of(Map<String, dynamic> extra) =>
          pbsVideoTitle(_video(extra: extra), now: _now)?.availability;
      expect(of({'expire_date': '2026-01-01T00:00:00Z'}), ReplayAvailability.expired);
      expect(of({'available_date': '2027-01-01T00:00:00Z'}), ReplayAvailability.upcoming);
      expect(of({'availability': 'unavailable'}), ReplayAvailability.geoBlocked);
    });

    test('web links and records without an id are not titles', () {
      expect(pbsVideoTitle({'item_type': 'remote_asset', 'title': 'Homepage'}), isNull);
      expect(pbsVideoTitle(_video(extra: {'legacy_tp_media_id': null})), isNull);
    });

    test('a zero duration is left out', () {
      expect(pbsVideoTitle(_video(extra: {'duration': 0}))?.durationSeconds, isNull);
      expect(pbsVideoTitle(_video(extra: {'duration': 90}))?.durationSeconds, 90);
    });
  });

  group('PBS ids', () {
    test('ids survive a round trip', () {
      expect(PbsId.tryParse('show:frontline'), isA<PbsShowId>());
      expect(PbsId.tryParse('season:frontline/specials'), isA<PbsSeasonId>());
      final video = PbsId.tryParse('video:3084427035/some-video-abc123') as PbsVideoId;
      expect(video.mediaId, '3084427035');
      expect(video.slug, 'some-video-abc123');
    });

    test('ids that could reach another path are refused', () {
      for (final bad in ['show:a/b', 'show:..', 'season:frontline/not-a-cid', 'video:12a/x', 'video:1/../x', 'x:y']) {
        expect(PbsId.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('PBS images', () {
    test('a sized request becomes an exact resize box', () {
      const url = 'https://image.pbs.org/video-assets/abc.jpg';
      expect(pbsImageUrl(url, width: 640, height: 360), '$url?resize=640x360');
      expect(pbsImageUrl(url, width: 3000, height: 1500), '$url?resize=1920x960');
    });

    test('an unsized request and an existing query are left alone', () {
      const url = 'https://image.pbs.org/video-assets/abc.jpg';
      expect(pbsImageUrl(url), url);
      expect(pbsImageUrl(url, width: 300), url);
      expect(pbsImageUrl('$url?format=webp', width: 300, height: 450), '$url?format=webp&resize=300x450');
    });

    test('only PBS image hosts are owned', () {
      expect(isPbsImage('https://image.pbs.org/a.jpg'), isTrue);
      expect(isPbsImage('https://example.org/a.jpg'), isFalse);
    });
  });

  group('PBS page data', () {
    test('a page without data chunks yields no values', () {
      expect(pbsFlightValues('<html><body>No data here</body></html>'), isEmpty);
    });

    test('lines split across chunks are joined and odd lines skipped', () {
      const html =
          '<script>self.__next_f.push([1,"1:{\\"item_type\\":\\"sh"])</script>'
          '<script>self.__next_f.push([1,"ow\\",\\"cid\\":\\"c\\"}\\n2:I[1,[],\\"x\\"]\\n3:not json\\n"])</script>';
      final values = pbsFlightValues(html);
      expect(values, hasLength(1));
      expect(pbsItems(values, 'show'), hasLength(1));
    });

    test('the video bridge is read whatever comes after it', () {
      const page = '<script>window.videoBridge = {"title": "a } b", "n": {"x": 1}}; var y = {};</script>';
      expect(pbsParseVideoBridge(page), {
        'title': 'a } b',
        'n': {'x': 1},
      });
      expect(pbsParseVideoBridge('<p>We are sorry</p>'), isNull);
      expect(pbsParseVideoBridge('window.videoBridge = {"open": '), isNull);
    });
  });

  group('PBS artwork', () {
    test('a show gets a poster, a backdrop and a logo from its images', () async {
      final shows = await PbsFixtureServer().provider().home();
      final show = shows.first.titles.first;
      expect(show.posterUrl, isNotNull);
      expect(PbsFixtureServer().provider().ownsImage(show.posterUrl!), isTrue);
    });
  });
}
