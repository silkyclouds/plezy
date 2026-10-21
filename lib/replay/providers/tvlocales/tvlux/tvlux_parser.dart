import '../tvlocales_images.dart';
import '../tvlocales_json_ld.dart';
import '../tvlocales_models.dart';
import '../tvlocales_text.dart';

final _showCardStart = RegExp(r'<div\s+class="news-card-eight[^"]*"\s*>');
final _showLink = RegExp(r'<h3>\s*<a\s+href="/replay/([^"/?#]+)"[^>]*>(.*?)</a>', dotAll: true);
final _pageTitle = RegExp(r'<h1[^>]*>(.*?)</h1>\s*<p>(.*?)</p>', dotAll: true);
final _heroImage = RegExp(r'emissionimg.*?<img\s[^>]*?\bsrc="([^"]+)"', dotAll: true);
final _episodeCardStart = RegExp(r'<article\s+class="news-card-thirteen[^"]*"\s*>');
final _cardLink = RegExp(r'<a\s+href="([^"]+)"');
final _cardTime = RegExp(r'<time\s+datetime="([^"]+)"');
final _episodeSuffix = RegExp(r'^/replay/[^/]+/[^/]+_\d+$');
const _cardSpan = 1500;

/// Reads the index of TV Lux shows (`/replay`): the cards repeat the first shows, so each slug is kept once.
List<TvShowCard> parseTvLuxShows(String html, Uri base) {
  final seen = <String>{};
  final shows = <TvShowCard>[];
  for (final card in html.split(_showCardStart).skip(1)) {
    final link = _showLink.firstMatch(card);
    if (link == null || !seen.add(link.group(1)!)) continue;
    shows.add(
      TvShowCard(slug: link.group(1)!, title: htmlFragmentText(link.group(2)!), imageUrl: firstImageUrl(base, card)),
    );
  }
  return shows;
}

/// Reads a TV Lux show page: the episode list comes from the page's JSON-LD `ItemList`, the thumbnails and
/// times from the cards that follow it. The site shows the 24 newest episodes only.
TvShowPage parseTvLuxShowPage(String html, Uri base, String showSlug) {
  final heading = _pageTitle.firstMatch(html);
  final hero = absoluteUrl(base, _heroImage.firstMatch(html)?.group(1));
  final cards = _cardDetails(html, base);
  return TvShowPage(
    title: htmlFragmentText(heading?.group(1) ?? ''),
    summary: meaningfulText(htmlFragmentText(heading?.group(2) ?? '')),
    posterUrl: hero,
    backdropUrl: hero,
    episodes: _episodes(html, showSlug, cards),
  );
}

typedef _CardDetails = ({String? imageUrl, DateTime? airDate});

Map<String, _CardDetails> _cardDetails(String html, Uri base) {
  final details = <String, _CardDetails>{};
  for (final card in html.split(_episodeCardStart).skip(1)) {
    final head = card.length > _cardSpan ? card.substring(0, _cardSpan) : card;
    final href = _cardLink.firstMatch(head)?.group(1);
    if (href == null) continue;
    final time = _cardTime.firstMatch(head)?.group(1);
    details.putIfAbsent(
      Uri.parse(href).path,
      () => (imageUrl: firstImageUrl(base, head), airDate: DateTime.tryParse(time ?? '')?.toUtc()),
    );
  }
  return details;
}

List<TvEpisodeCard> _episodes(String html, String showSlug, Map<String, _CardDetails> cards) {
  final list = jsonLdOfType(readJsonLd(html), const ['ItemList']);
  final items = list?['itemListElement'];
  if (items is! List) return const [];
  final prefix = '/replay/$showSlug/';
  return [
    for (final item in items.whereType<Map<String, dynamic>>())
      if (_pathOf(item['url']) case final path? when path.startsWith(prefix) && _episodeSuffix.hasMatch(path))
        TvEpisodeCard(
          path: path.substring(prefix.length),
          title: htmlFragmentText(item['name'] as String? ?? ''),
          airDate: cards[path]?.airDate,
          imageUrl: cards[path]?.imageUrl,
        ),
  ];
}

String? _pathOf(Object? url) => url is String ? Uri.tryParse(url)?.path : null;
