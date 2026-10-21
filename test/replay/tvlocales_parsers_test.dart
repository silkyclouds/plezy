import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/providers/tvlocales/antennecentre_provider.dart';
import 'package:plezy/replay/providers/tvlocales/canalzoom_provider.dart';
import 'package:plezy/replay/providers/tvlocales/drupal/drupal_show_page_parser.dart';
import 'package:plezy/replay/providers/tvlocales/drupal/drupal_shows_parser.dart';
import 'package:plezy/replay/providers/tvlocales/freecaster_player.dart';
import 'package:plezy/replay/providers/tvlocales/telemb_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_duration.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_episode_page.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_ids.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_images.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_numbering.dart';
import 'package:plezy/replay/providers/tvlocales/tvlocales_text.dart';
import 'package:plezy/replay/providers/tvlocales/tvlux/tvlux_parser.dart';

import 'tvlocales_fixtures.dart';

final _telemb = Uri.parse('https://www.telemb.be');
final _telesambre = Uri.parse('https://www.telesambre.be');
final _tvlux = Uri.parse('https://www.tvlux.be');
const _telembBackdrop =
    '/cdn/ff/4eNyLTHgEcPy8YdrNxYRCsVYojkCHfTFIGySmeVajJM/1713457563/public/styles/program_large/public/2024-04/00000011_les_infos.png?itok=wbnJSXWa';

Map<String, dynamic> _json(String name) => jsonDecode(tvLocalesFixture(name)) as Map<String, dynamic>;

void main() {
  group('text helpers', () {
    test('character references and tags are decoded', () {
      expect(
        htmlFragmentText('C&#039;est <b>pas</b> si&nbsp;compliqu&#233; &amp; long'),
        "C'est pas si compliqué & long",
      );
      expect(decodeEntities('&#x41;&#xZZ;&#99999999;'), 'A&#xZZ;&#99999999;');
    });

    test('Windows-1252 control characters become punctuation', () {
      expect(tidyText('l\u0092archéologie \u0096 wallonne'), 'l’archéologie – wallonne');
    });

    test('placeholder descriptions count as no description', () {
      expect(meaningfulText(' '), isNull);
      expect(meaningfulText('. '), isNull);
      expect(meaningfulText(' Les infos '), 'Les infos');
    });

    test('search folding ignores case, accents and punctuation', () {
      expect(foldForSearch("C'est pas si compliqué !"), 'c est pas si complique');
      expect(foldForSearch('ÉCOLE'), foldForSearch('école'));
    });

    test('durations are read from minute text and ISO 8601', () {
      expect(parseDurationText('29 min'), 29 * 60);
      expect(parseDurationText('1 h 05'), 3900);
      expect(parseDurationText('publié le 10/10/2026'), isNull);
      expect(parseIsoDuration('PT22M4S'), 1324);
      expect(parseIsoDuration('PT1H'), 3600);
      expect(parseIsoDuration('soon'), isNull);
    });
  });

  group('numbering', () {
    test('an explicit episode number in the title is derived', () {
      expect(deriveEpisodeNumber('Au fil des saisons - Épisode 3'), 3);
      expect(deriveEpisodeNumber('Ep. 12 : la suite'), 12);
      expect(deriveEpisodeNumber('Episode n° 4'), 4);
    });

    test('dated titles carry no episode number', () {
      expect(deriveEpisodeNumber('Les Infos du mardi 20 octobre 2026'), isNull);
      expect(deriveEpisodeNumber('Atout Sports du 18 octobre: partie 2'), isNull);
      expect(deriveEpisodeNumber('Le repas des Epicuriens'), isNull);
    });

    test('a season label gives its number, else the fallback', () {
      expect(seasonNumberFromLabel('Saison 2024', fallback: 1), 2024);
      expect(seasonNumberFromLabel('Hiver', fallback: 7), 7);
    });
  });

  group('native ids', () {
    test('shows, seasons and episodes round trip', () {
      for (final raw in [
        'les-infos',
        'les-infos/~62881',
        'les-infos/~all',
        'les-infos/ep-1/41114',
        'jt/jt-du-1_52614',
      ]) {
        expect(TvLocalesId.tryParse(raw)!.nativeId, raw);
      }
      expect(TvLocalesId.tryParse('les-infos/~all')!.isSeason, isTrue);
      expect(TvLocalesId.tryParse('les-infos/ep-1/41114')!.isEpisode, isTrue);
      expect(TvLocalesId.tryParse('les-infos')!.isShow, isTrue);
    });

    test('anything that is not a plain path is rejected', () {
      for (final raw in ['', '../etc', 'a/../b', 'a//b', 'a?b', 'a/b#c', '~all/x', 'a/b/c/d/e', 'a b']) {
        expect(TvLocalesId.tryParse(raw), isNull, reason: raw);
      }
    });
  });

  group('Drupal show index', () {
    test('relative covers resolve against the station host', () {
      final shows = parseDrupalShows(tvLocalesFixture('drupal_emissions_telesambre.html'), _telesambre);
      expect(shows.map((s) => s.slug), ['le-jt', 'c-decouvrir', 'pense-betes', 'artheme']);
      expect(shows.first.title, 'Le JT');
      expect(shows.first.imageUrl, startsWith('https://www.telesambre.be/sites/default/files/styles/portrait_large/'));
    });

    test('a show repeated in the slider is listed once, with decoded title', () {
      final shows = parseDrupalShows(tvLocalesFixture('drupal_emissions_telemb.html'), _telemb);
      expect(shows.map((s) => s.title), ["C'est pas si compliqué !", 'Les infos', 'Atout Sports', 'On Improvise']);
      expect(shows.first.imageUrl, startsWith('https://www.telemb.be/cdn/ff/'));
      expect(shows.first.imageUrl, contains('itok='));
    });

    test('a page without covers lists nothing', () {
      expect(parseDrupalShows('<html></html>', _telemb), isEmpty);
    });
  });

  group('Drupal show page', () {
    test('header, artwork, episodes and next slice are read', () {
      final page = parseDrupalShowPage(tvLocalesFixture('drupal_show_telemb_les_infos.html'), _telemb, 'les-infos');
      expect(page.title, 'Les infos');
      expect(page.summary, isNull, reason: 'the summary only repeats the title');
      expect(page.posterUrl, contains('/styles/portrait_large/'));
      expect(page.backdropUrl, 'https://www.telemb.be$_telembBackdrop');
      expect(page.seasons, isEmpty);
      expect(page.hasNext, isTrue);
      expect(page.episodes.map((e) => e.path), [
        'les-infos-du-mardi-20-octobre-2026/41114',
        'les-infos-du-lundi-19-octobre-2026/41113',
        'les-infos-du-samedi-17-octobre-2026/41112',
      ]);
      final first = page.episodes.first;
      expect(first.title, 'Les Infos du mardi 20 octobre 2026');
      expect(first.airDate, DateTime.utc(2026, 10, 20, 16, 20));
      expect(first.durationSeconds, 20 * 60);
      expect(first.imageUrl, contains('/styles/one_quarter_lg/'));
    });

    test('the last slice has no next link', () {
      final page = parseDrupalShowPage(
        tvLocalesFixture('drupal_show_telemb_les_infos_last.html'),
        _telemb,
        'les-infos',
      );
      expect(page.hasNext, isFalse);
      expect(page.episodes, hasLength(2));
    });

    test('season filter links are read in page order', () {
      final page = parseDrupalShowPage(tvLocalesFixture('drupal_show_telesambre_le_jt.html'), _telesambre, 'le-jt');
      expect([for (final s in page.seasons) (s.facet, s.label)], [('62881', 'Saison 2024'), ('59856', 'Saison 2023')]);
    });

    test('an episode without a duration keeps its date', () {
      final page = parseDrupalShowPage(tvLocalesFixture('drupal_show_telesambre_le_jt.html'), _telesambre, 'le-jt');
      final last = page.episodes.last;
      expect(last.path, 'jt-du-vendredi-16-octobre-2026/83378');
      expect(last.durationSeconds, isNull);
      expect(last.airDate, DateTime.utc(2026, 10, 16, 17, 3));
    });

    test('articles without the camera badge are left out', () {
      final page = parseDrupalShowPage(tvLocalesFixture('drupal_show_tvcom_pedagoscope.html'), _telemb, 'pedagoscope');
      expect(page.episodes.map((e) => e.path), [
        'pedagoscope-doit-encourager-les-jeunes-sennuyer/58521',
        'pedagoscope-05-05-26-evras/57322',
      ]);
      expect(page.episodes.first.title, "Pedagoscope : Doit-on encourager les jeunes à s'ennuyer?");
    });

    test('a show of articles only has no episodes', () {
      final page = parseDrupalShowPage(tvLocalesFixture('drupal_show_tvcom_articles_only.html'), _telemb, 'le-22h30');
      expect(page.episodes, isEmpty);
    });

    test('links that belong to another show are ignored', () {
      final page = parseDrupalShowPage(tvLocalesFixture('drupal_show_telemb_les_infos.html'), _telemb, 'atout-sports');
      expect(page.episodes, isEmpty);
    });
  });

  group('episode pages', () {
    test('a Drupal page gives the video id and its article data', () {
      final page = parseEpisodePage(tvLocalesFixture('drupal_episode_telemb.html'));
      expect(page.videoId, 'a30728c1-5ff5-4435-a10b-0f0454743de2');
      expect(page.title, 'Les Infos du mardi 20 octobre 2026');
      expect(page.showName, 'Les infos');
      expect(page.airDate, DateTime.utc(2026, 10, 20, 16, 20));
      expect(page.summary, 'Retrouvez Les Infos, du lundi au samedi à 18h.');
    });

    test('an article without a player has no video id', () {
      final page = parseEpisodePage(tvLocalesFixture('drupal_episode_article_tvcom.html'));
      expect(page.videoId, isNull);
      expect(page.title, 'Pedagoscope : 19-05-26 : La sécurisation des enfants');
    });

    test('a TV Lux page gives series, duration and a player split over lines', () {
      final page = parseEpisodePage(tvLocalesFixture('tvlux_episode_jt.html'));
      expect(page.videoId, 'a30722b3-e0b3-4599-8e73-02bc4fad37df');
      expect(page.title, 'JT du 20/10/2026');
      expect(page.showName, 'JT');
      expect(page.durationSeconds, 13 * 60 + 41);
    });

    test('control characters in a TV Lux description are normalised', () {
      final page = parseEpisodePage(tvLocalesFixture('tvlux_episode_archeosphere.html'));
      expect(page.summary, startsWith('2014 a célébré les 25 ans de l’archéologie'));
      expect(page.showName, 'ArchéoSphére');
      expect(page.durationSeconds, 1324);
    });

    test('a page with no data at all is still readable', () {
      final page = parseEpisodePage('<html><body>Not an episode</body></html>');
      expect([page.videoId, page.title, page.airDate], [null, null, null]);
    });
  });

  group('TV Lux pages', () {
    test('the index lists each show once with its image', () {
      final shows = parseTvLuxShows(tvLocalesFixture('tvlux_replay_index.html'), _tvlux);
      expect(shows.map((s) => s.slug), ['jt', 'le-22h30-le-journal-de-vivre-ici', 'l-hebdo', 'archeosphere']);
      expect(shows.first.imageUrl, 'https://www.tvlux.be/medias/emissions/00000133_info-le-journal.jpeg');
      expect(shows.last.title, 'ArchéoSphére');
    });

    test('a show page lists the episodes of its JSON-LD with card details', () {
      final page = parseTvLuxShowPage(tvLocalesFixture('tvlux_show_jt.html'), _tvlux, 'jt');
      expect(page.title, 'JT');
      expect(page.summary, startsWith('Chaque jour à 18h'));
      expect(page.posterUrl, 'https://www.tvlux.be/medias/emissions/00000048_le-journal-2017.jpeg');
      expect(page.seasons, isEmpty);
      expect(page.hasNext, isFalse);
      expect(page.episodes.map((e) => e.path), [
        'jt-du-20-10-2026_52614',
        'jt-du-19-10-2026_52613',
        'jt-du-16-10-2026_52612',
        'jt-du-15-10-2026_52611',
        'jt-du-14-10-2026_52610',
      ]);
      expect(page.episodes.first.airDate, DateTime.utc(2026, 10, 20, 16, 30));
      expect(page.episodes.first.imageUrl, startsWith('https://www.tvlux.be/site/layout/images/'));
      expect(page.episodes.last.airDate, isNull, reason: 'only the first three episodes have cards in the fixture');
    });

    test('a page without a list has no episodes', () {
      expect(parseTvLuxShowPage('<html></html>', _tvlux, 'jt').episodes, isEmpty);
    });
  });

  group('Freecaster player configuration', () {
    test('the HLS master and the MP4 renditions are separated', () {
      final video = parseFreecasterConfig(_json('freecaster_embed_telemb.json'))!;
      expect(video.hls.toString(), endsWith('/C3UteH5DqyJ3fYhBkGVJ1WyS.m3u8'));
      expect(video.mp4, hasLength(4));
      expect(video.durationSeconds, 1176);
      expect(video.subtitles, isEmpty);
    });

    test('the poster is a size template only when HD exists', () {
      expect(parseFreecasterConfig(_json('freecaster_embed_telemb.json'))!.poster, contains('%{SIZE}'));
      final archive = parseFreecasterConfig(_json('freecaster_embed_tvlux_archive.json'))!;
      expect(archive.poster, endsWith('/640x360.jpg'));
    });

    test('subtitle tracks are offered as sidecar files', () {
      final video = parseFreecasterConfig(_json('freecaster_embed_tvlux_subtitled.json'))!;
      expect(video.subtitles.single.languageCode, 'fr');
      expect(video.subtitles.single.url.path, endsWith('.vtt'));
    });

    test('a document without a video object is not a configuration', () {
      expect(parseFreecasterConfig(const {}), isNull);
    });
  });

  group('artwork references', () {
    test('a station owns its site files and its own Freecaster folder', () {
      const poster = 'https://tvlocales-posters.freecaster.com/videos';
      expect(ownsTvLocalesImage(teleMbStation, 'https://www.telemb.be/cdn/ff/x.png?itok=1'), isTrue);
      expect(ownsTvLocalesImage(teleMbStation, 'https://www.tvlux.be/medias/emissions/a.jpeg'), isFalse);
      expect(ownsTvLocalesImage(teleMbStation, '$poster/telemb/a/b/%{SIZE}.jpg'), isTrue);
      expect(ownsTvLocalesImage(teleMbStation, '$poster/tvlux/a/b/%{SIZE}.jpg'), isFalse);
      expect(ownsTvLocalesImage(antenneCentreStation, '$poster/actv/a/b/%{SIZE}.jpg'), isTrue);
      expect(ownsTvLocalesImage(canalZoomStation, 'not a url'), isFalse);
    });

    test('a size template takes the smallest rendition that covers the width', () {
      const template = 'https://tvlocales-posters.freecaster.com/videos/telemb/a/b/%{SIZE}.jpg';
      expect(tvLocalesImageUrl(template, width: 300), endsWith('/320x180.jpg'));
      expect(tvLocalesImageUrl(template, width: 700), endsWith('/854x480.jpg'));
      expect(tvLocalesImageUrl(template, width: 5000), endsWith('/1920x1080.jpg'));
      expect(tvLocalesImageUrl(template), endsWith('/640x360.jpg'));
    });

    test('a plain address is returned as it is', () {
      const plain = 'https://www.telemb.be/cdn/ff/x.png?itok=1&v=2';
      expect(tvLocalesImageUrl(plain, width: 300), plain);
    });
  });
}
