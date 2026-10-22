import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_ids.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_images.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_mapper.dart';
import 'package:plezy/replay/providers/aljazeera/aljazeera_text.dart';

import 'aljazeera_fake_site.dart';

void defineUnitCases() {
  group('Al Jazeera ids', () {
    test('each kind of title survives a round trip', () {
      for (final native in ['inside-story', 'inside-story/2026', 'inside-story/e/6407140246112', 'v/6407214258112']) {
        expect(AljazeeraId.tryParse(native)!.toString(), native);
      }
    });

    test('shapes that name nothing are rejected', () {
      for (final native in ['', '/', 'a/', 'a/b', 'a/e', 'a/e/', 'a/2026/x', 'v', 'v/', 'a/b/c/d']) {
        expect(AljazeeraId.tryParse(native), isNull, reason: native);
      }
    });

    test('kinds are told apart', () {
      expect(AljazeeraId.tryParse('v/1')!.isClip, isTrue);
      expect(AljazeeraId.tryParse('a/2026')!.isSeason, isTrue);
      expect(AljazeeraId.tryParse('a/e/1')!.isEpisode, isTrue);
      expect(AljazeeraId.tryParse('a')!.isShow, isTrue);
      expect(AljazeeraId.tryParse('a/e/1')!.showRef.nativeId, 'a');
    });
  });

  group('Al Jazeera text', () {
    test('numeric entities become characters', () {
      expect(aljazeeraText('Ukraine&#8217;s &#8220;rescue&#8221;'), 'Ukraine’s “rescue”');
      expect(aljazeeraText('Gaza&#039;s &amp; Rafah &#x41;'), "Gaza's & Rafah A");
    });

    test('markup is removed and a broken entity is left alone', () {
      expect(aljazeeraText('<p>One</p>\n<p><strong>Two</strong></p>'), 'One\n\nTwo');
      expect(aljazeeraText('a &#99999999; b'), 'a &#99999999; b');
      expect(aljazeeraText(null), '');
    });

    test('clock strings give seconds', () {
      expect(aljazeeraDurationSeconds('27:45'), 1665);
      expect(aljazeeraDurationSeconds('01:19'), 79);
      expect(aljazeeraDurationSeconds('1:02:03'), 3723);
      for (final bad in [null, '', '45', 'a:b', '1:2:3:4', '-1:00']) {
        expect(aljazeeraDurationSeconds(bad), isNull, reason: '$bad');
      }
    });

    test('a date without a zone is read as UTC', () {
      expect(aljazeeraDate('2026-10-20T18:45:23'), DateTime.utc(2026, 10, 20, 18, 45, 23));
      expect(aljazeeraDate('2026-10-20T18:45:23+02:00'), DateTime.utc(2026, 10, 20, 16, 45, 23));
      expect(aljazeeraDate('2026-10-20T15:57:57.945Z'), DateTime.utc(2026, 10, 20, 15, 57, 57, 945));
      expect(aljazeeraDate(''), isNull);
      expect(aljazeeraDate(null), isNull);
    });
  });

  group('Al Jazeera mapping', () {
    test('a post without a video is not an episode', () {
      for (final post in recordedPosts('section_posts_witness_youtube_only')) {
        expect(aljazeeraVideoId(post), isNull);
        expect(aljazeeraEpisode(post), isNull);
        expect(aljazeeraClip(post), isNull);
      }
    });

    test('a post that names no programme takes the one the caller knows', () {
      final post = recordedPosts('section_posts_inside_story').first..remove('programs');
      expect(aljazeeraEpisode(post), isNull);
      expect(aljazeeraEpisode(post, programme: 'inside-story', showTitle: 'Inside Story')!.showTitle, 'Inside Story');
    });

    test('a synopsis that only repeats the title is dropped', () {
      final clip = aljazeeraClip(recordedPosts('section_posts_newsfeed_clips').first)!;
      expect(clip.summary, isNull);
      expect(aljazeeraEpisode(recordedPosts('section_posts_inside_story').first)!.summary, contains('World Food'));
    });
  });

  group('Al Jazeera images', () {
    const upload = 'https://www.aljazeera.com/wp-content/uploads/2026/10/image-1792261027.jpg';

    test('an upload is resized to the box and cropped by the site', () {
      expect(aljazeeraImageUrl(upload, width: 400, height: 225), '$upload?resize=400%2C225&quality=80');
    });

    test('a missing side is derived for a 16:9 frame', () {
      expect(aljazeeraImageUrl(upload, width: 640), '$upload?resize=640%2C360&quality=80');
      expect(aljazeeraImageUrl(upload, height: 450), '$upload?resize=800%2C450&quality=80');
      expect(aljazeeraImageUrl(upload), '$upload?resize=770%2C433&quality=80');
    });

    test('sizes are capped and an earlier query is replaced', () {
      expect(
        aljazeeraImageUrl('$upload?resize=1%2C1', width: 5000, height: 4000),
        '$upload?resize=1920%2C1920&quality=80',
      );
    });

    test('Brightcove frames are used as they are', () {
      const frame = 'https://cf-images.eu-west-1.prod.boltdns.net/v1/static/1/2/3/1920x1080/match/image.jpg';
      expect(aljazeeraImageUrl(frame, width: 300), frame);
      expect(isAljazeeraImage(frame), isTrue);
    });

    test('only the site uploads and Brightcove frames are owned', () {
      expect(isAljazeeraImage(upload), isTrue);
      expect(isAljazeeraImage('https://example.com/wp-content/a.jpg'), isFalse);
      expect(isAljazeeraImage('https://www.aljazeera.com/video/inside-story'), isFalse);
    });

    test('shows and episodes point at uploads, not at the original file', () {
      final show = aljazeeraShow(
        ((aljazeeraFixture('programs_tv_shows')['data'] as Map)['programs'] as List).first as Map<String, dynamic>,
      )!;
      expect(show.kind, ReplayKind.show);
      expect(show.backdropUrl, startsWith('https://www.aljazeera.com/wp-content/uploads/'));
      expect(show.backdropUrl, isNot(contains('?')));
    });
  });
}
