import 'dart:math' as math;

import '../tvlocales_duration.dart';
import '../tvlocales_images.dart';
import '../tvlocales_models.dart';
import '../tvlocales_text.dart';

final _teaserStart = RegExp(r'<article\s+id="node-\d+"\s+class="teaser-item"\s*>');
final _videoBadge = RegExp(r'class="teaser-item\s+camera-icon"');
final _episodeLink = RegExp(r'href="/(?:replay/)?emission/([^"?#]+)"');
final _time = RegExp(r'<time\s+datetime="([^"]+)"\s*>(.*?)</time>', dotAll: true);
final _durationItem = RegExp(r'field-item">\s*([^<]*?)\s*<');
final _heading = RegExp(r'<h2>\s*<span>(.*?)</span>', dotAll: true);
final _pageTitle = RegExp(r'<h1>\s*<span>(.*?)</span>', dotAll: true);
final _summary = RegExp(r'field-program-summary.*?<div class="field-item">(.*?)</div>', dotAll: true);
final _landscape = RegExp(r'srcset="([^"\s]*styles/program_large[^"\s]*)');
final _facetList = RegExp(r'<ul\s+data-drupal-facet-id="saison".*?</ul>', dotAll: true);
final _facetLink = RegExp(r'<a\s[^>]*data-drupal-facet-item-value="([^"]+)"[^>]*>(.*?)</a>', dotAll: true);
final _facetLabel = RegExp(r'facet-item__value">(.*?)</span>', dotAll: true);
final _nextPage = RegExp(r'<a\s[^>]*rel="next"');
const _teaserSpan = 8000;
const _badgeWindow = 600;

/// Reads one page of a Drupal show: header, season filter and the episodes that have a video.
///
/// Cards without the camera badge are articles with no video, so they are left out.
TvShowPage parseDrupalShowPage(String html, Uri base, String showSlug) {
  final header = _header(html);
  final title = htmlFragmentText(_pageTitle.firstMatch(html)?.group(1) ?? '');
  return TvShowPage(
    title: title,
    summary: _summaryOf(html, title),
    posterUrl: firstImageUrl(base, header),
    backdropUrl: absoluteUrl(base, _landscape.firstMatch(header)?.group(1)),
    seasons: _seasons(html),
    episodes: _episodes(html, base, showSlug),
    hasNext: _nextPage.hasMatch(html),
  );
}

String _header(String html) {
  final start = html.indexOf('content-media');
  final end = html.indexOf('<h1');
  return start >= 0 && end > start ? html.substring(start, end) : '';
}

String? _summaryOf(String html, String title) {
  final text = meaningfulText(htmlFragmentText(_summary.firstMatch(html)?.group(1) ?? ''));
  return text == null || foldForSearch(text) == foldForSearch(title) ? null : text;
}

List<TvSeasonLink> _seasons(String html) {
  final list = _facetList.firstMatch(html)?.group(0);
  if (list == null) return const [];
  return [
    for (final link in _facetLink.allMatches(list))
      if (_facetLabel.firstMatch(link.group(2)!) case final label?)
        TvSeasonLink(facet: link.group(1)!, label: htmlFragmentText(label.group(1)!)),
  ];
}

List<TvEpisodeCard> _episodes(String html, Uri base, String showSlug) {
  final starts = _teaserStart.allMatches(html).map((m) => m.start).toList();
  final episodes = <TvEpisodeCard>[];
  for (var i = 0; i < starts.length; i++) {
    final end = i + 1 < starts.length ? starts[i + 1] : html.length;
    final card = html.substring(starts[i], math.min(end, starts[i] + _teaserSpan));
    final episode = _episode(card, base, showSlug);
    if (episode != null) episodes.add(episode);
  }
  return episodes;
}

TvEpisodeCard? _episode(String card, Uri base, String showSlug) {
  if (!_videoBadge.hasMatch(card.substring(0, math.min(card.length, _badgeWindow)))) return null;
  final path = _episodePath(card, showSlug);
  final title = _heading.firstMatch(card)?.group(1);
  if (path == null || title == null) return null;
  final time = _time.firstMatch(card);
  return TvEpisodeCard(
    path: path,
    title: htmlFragmentText(title),
    airDate: time == null ? null : DateTime.tryParse(time.group(1)!)?.toUtc(),
    durationSeconds: parseDurationText(time == null ? null : _durationItem.firstMatch(time.group(2)!)?.group(1)),
    imageUrl: firstImageUrl(base, card),
  );
}

/// The `<episode>/<node>` part of the card link, only when the link belongs to [showSlug].
String? _episodePath(String card, String showSlug) {
  final parts = _episodeLink.firstMatch(card)?.group(1)?.split('/') ?? const <String>[];
  final isEpisode = parts.length == 3 && parts[0] == showSlug && int.tryParse(parts[2]) != null;
  return isEpisode ? '${parts[1]}/${parts[2]}' : null;
}
