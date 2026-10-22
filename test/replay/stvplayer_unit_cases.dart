import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_access.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_images.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_numbering.dart';
import 'package:plezy/replay/providers/stvplayer/stvplayer_refs.dart';

import 'stvplayer_test_support.dart';

/// Pure rules: numbering, artwork URLs, availability flags and the UK allow list.
void stvUnitCases() {
  group('STV Player numbering', () {
    test('series names with a number keep it', () {
      expect(stvSeasonNumbers(['Series 3', 'Series 10', 'Series 4 ']), [3, 10, 4]);
    });

    test('other names follow the highest numbered series in list order', () {
      expect(stvSeasonNumbers(['Series 1', 'Specials', 'Series 2', 'Behind the scenes']), [1, 3, 2, 4]);
      expect(stvSeasonNumbers(['Episodes 1 - 25', 'Episodes 26 - 50']), [1, 2]);
      expect(stvSeasonNumbers(['USA', 'Australia']), [1, 2]);
    });

    test('two series claiming the same number fall back to list order', () {
      expect(stvSeasonNumbers(['Series 1', 'Series 1 ', 'Series 2']), [1, 2, 3]);
    });

    test('an episode number is read from the title when the series gives none', () {
      expect(stvEpisodeNumberFromTitle('Episode 3'), 3);
      expect(stvEpisodeNumberFromTitle('Episode 12 - Marriage on the Slopes'), 12);
      expect(stvEpisodeNumberFromTitle('1. Memories of Bambi'), 1);
      expect(stvEpisodeNumberFromTitle('Wed 21 Oct, 10.40 pm'), isNull);
      expect(stvEpisodeNumberFromTitle('Episodes of the week'), isNull);
    });

    test('the broadcast date is read from the episode guid', () {
      expect(stvAirDateFromGuid('scotland-tonight-20261021-2240'), DateTime.utc(2026, 10, 21));
      expect(stvAirDateFromGuid('catchup-ac2-mez-archive-taggart-deathtrap-20020114.mpg'), DateTime.utc(2002, 1, 14));
      expect(stvAirDateFromGuid('taggart-series-1-episode-1'), isNull);
      expect(stvAirDateFromGuid('show-20261345-2240'), isNull);
    });

    test('native ids round trip through their references', () {
      expect(StvTarget.parse(stvShowRef('taggart').nativeId).kind, StvTargetKind.show);
      final season = StvTarget.parse(stvSeasonRef('taggart', 'taggart-series-2').nativeId);
      expect((season.kind, season.programme, season.series), (StvTargetKind.season, 'taggart', 'taggart-series-2'));
      expect(StvTarget.parse(stvEpisodeRef(42).nativeId).id, '42');
      expect(StvTarget.parse(stvClipRef('7').nativeId).kind, StvTargetKind.clip);
    });
  });

  group('STV Player artwork', () {
    const mainImage = [
      {'id': 801706, 'width': 1920, 'height': 1080, 'imageType': 'mainImage'},
      {'id': 801709, 'width': 1200, 'height': 340, 'imageType': 'titleImage'},
    ];

    test('a reference picks the image by type and keeps the resizer template', () {
      final reference = stvPlayerImageReference(mainImage)!;
      expect(reference, startsWith('https://player.api.stv.tv/v1/images/801706/rendition/?redirect=true&width=['));
      expect(stvPlayerImageReference(mainImage, type: 'squareImage'), isNull);
      expect(stvPlayerImageReference(mainImage, type: 'squareImage', anyImage: true), isNotNull);
      expect(stvPlayerImageReference(null), isNull);
    });

    test('a single image object, as categories have, works too', () {
      expect(stvPlayerImageReference(mainImage.first), contains('/801706/'));
    });

    test('sizes snap to a few widths and keep the requested crop', () {
      final reference = stvPlayerImageReference(mainImage)!;
      expect(stvPlayerImageUrl(reference, width: 300, height: 450), endsWith('width=320&height=480'));
      expect(stvPlayerImageUrl(reference, width: 1280, height: 720), endsWith('width=1280&height=720'));
      expect(stvPlayerImageUrl(reference, width: 5000), endsWith('width=1920&height=1080'));
      expect(stvPlayerImageUrl(reference), endsWith('width=640&height=360'));
    });

    test('a width alone keeps the picture own proportions', () {
      final logo = stvPlayerImageReference(mainImage, type: 'titleImage')!;
      expect(stvPlayerImageUrl(logo, width: 480), endsWith('width=480&height=136'));
      expect(stvPlayerImageUrl(logo, width: 480), isNot(contains('#')));
    });

    test('foreign references are left alone', () {
      expect(isStvPlayerImage('https://example.test/a.jpg'), isFalse);
      expect(stvPlayerImageUrl('https://example.test/a.jpg', width: 300), 'https://example.test/a.jpg');
    });
  });

  group('STV Player availability flags', () {
    Map<String, dynamic> episode() => Map.of(stvFixture('episode_detail')['results'] as Map<String, dynamic>);

    test('an open episode inside its window is playable', () {
      expect(stvPlayerAvailability(episode(), stvNow), ReplayAvailability.playable);
    });

    test('a window with no start and no end is playable', () {
      expect(stvPlayerAvailability(episode()..['availability'] = null, stvNow), ReplayAvailability.playable);
    });

    test('premium flags on the episode or its programme need an account', () {
      for (final flag in ['vipExclusive', 'svodExclusive', 'premierSportsExclusive']) {
        expect(stvPlayerAvailability(episode()..[flag] = true, stvNow), ReplayAvailability.loginRequired, reason: flag);
      }
      final viaProgramme = episode();
      (viaProgramme['programme'] as Map<String, dynamic>)['svodExclusive'] = true;
      expect(stvPlayerAvailability(viaProgramme, stvNow), ReplayAvailability.loginRequired);
    });

    test('protection outranks every other state', () {
      final item = episode()
        ..['drmEnabled'] = true
        ..['vipExclusive'] = true;
      expect(stvPlayerAvailability(item, stvNow), ReplayAvailability.drmProtected);
    });
  });

  group('STV Player UK allow list', () {
    test('an episode limited to the UK is blocked for other countries only', () {
      final restrictions = StvPlayerRestrictions();
      final ref = stvEpisodeRef(1);
      restrictions.note(ref, ['uk', 'itv']);
      expect(restrictions.verdict(ref, 'BE'), ReplayAvailability.geoBlocked);
      expect(restrictions.verdict(ref, 'GB'), isNull);
      expect(restrictions.verdict(ref, 'uk'), isNull);
    });

    test('regional tokens are inside the UK as well', () {
      final restrictions = StvPlayerRestrictions();
      final ref = stvEpisodeRef(2);
      restrictions.note(ref, ['aberdeen', 'glasgow']);
      expect(restrictions.verdict(ref, 'FR'), ReplayAvailability.geoBlocked);
      expect(restrictions.verdict(ref, 'GB'), isNull);
    });

    test('an empty or missing list says nothing', () {
      final restrictions = StvPlayerRestrictions();
      restrictions.note(stvEpisodeRef(3), const []);
      restrictions.note(stvEpisodeRef(4), null);
      expect(restrictions.verdict(stvEpisodeRef(3), 'BE'), isNull);
      expect(restrictions.verdict(stvEpisodeRef(4), 'BE'), isNull);
      expect(restrictions.verdict(stvEpisodeRef(5), 'BE'), isNull);
    });
  });
}
