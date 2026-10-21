import '../tvlocales_images.dart';
import '../tvlocales_models.dart';
import '../tvlocales_text.dart';

final _cardStart = RegExp(r'<div\s+class="view-mode-portrait"\s*>');
final _titleLink = RegExp(r'<h4>\s*<a\s+href="/emission/([^"/?#]+)"\s*>\s*<span>(.*?)</span>', dotAll: true);

/// Reads the programme covers of a Drupal station's `/emissions` page, once per show and in page order.
List<TvShowCard> parseDrupalShows(String html, Uri base) {
  final seen = <String>{};
  final shows = <TvShowCard>[];
  for (final cover in html.split(_cardStart).skip(1)) {
    final link = _titleLink.firstMatch(cover);
    if (link == null || !seen.add(link.group(1)!)) continue;
    shows.add(
      TvShowCard(slug: link.group(1)!, title: htmlFragmentText(link.group(2)!), imageUrl: firstImageUrl(base, cover)),
    );
  }
  return shows;
}
