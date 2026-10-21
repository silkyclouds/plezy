import 'tvlocales_duration.dart';
import 'tvlocales_json_ld.dart';
import 'tvlocales_models.dart';
import 'tvlocales_text.dart';

final _playerTag = RegExp(r'<div[^>]*freecaster-player[^>]*>', dotAll: true);
final _videoId = RegExp(r'data-video-id\s*=\s*"([0-9a-fA-F-]{36})"');
const _pageTypes = ['TVEpisode', 'NewsArticle', 'Article'];

/// Reads an episode page of any station: the Freecaster video id, and the metadata the page carries as JSON-LD.
TvEpisodePage parseEpisodePage(String html) {
  final data = jsonLdOfType(readJsonLd(html), _pageTypes);
  final video = data?['video'];
  final series = data?['partOfSeries'];
  return TvEpisodePage(
    videoId: _findVideoId(html),
    title: _text((video is Map ? video['name'] : null) ?? data?['headline']),
    showName: _text((series is Map ? series['name'] : null) ?? data?['articleSection']),
    summary: _text(data?['description']),
    imageUrl: firstString(data?['image']),
    airDate: _date(data?['datePublished']),
    durationSeconds: parseIsoDuration(video is Map ? video['duration'] as String? : null),
  );
}

String? _findVideoId(String html) {
  final tag = _playerTag.firstMatch(html)?.group(0);
  final inTag = tag == null ? null : _videoId.firstMatch(tag);
  return (inTag ?? _videoId.firstMatch(html))?.group(1);
}

String? _text(Object? value) => meaningfulText(value is String ? decodeEntities(value) : null);

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
