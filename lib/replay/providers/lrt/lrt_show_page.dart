import '../../text/html_text.dart';
import 'lrt_dates.dart';
import 'lrt_flight.dart';
import 'lrt_images.dart';
import 'lrt_json.dart';
import 'lrt_models.dart';
import 'lrt_refs.dart';

/// Reads a programme page. The site embeds the programme, its season list and the first recordings in the page's
/// streamed payload; there is no other source for the seasons. Returns null when the payload has no programme.
LrtShowPage? parseLrtShowPage(Object? html, {required String slug}) {
  if (html is! String) return null;
  final text = lrtFlightText(html);
  final show = lrtFlightObject(text, '"show":', accept: (m) => m['seasons'] is List && lrtString(m['title']) != null);
  if (show == null) return null;
  final listing = lrtFlightObject(text, '"episodes":', accept: (m) => m['items'] is List);
  return LrtShowPage(
    slug: slug,
    title: lrtString(show['title'])!,
    summary: _summary(show['description']),
    imageTemplate: _picture(show['image']),
    seasons: _seasons(show['seasons']),
    episodes: [for (final item in lrtJsonObjects(listing?['items'])) ?_episode(item)],
    episodeTotal: lrtInt(listing?['total']),
  );
}

List<LrtSeason> _seasons(Object? raw) {
  final seen = <String>{};
  final seasons = <LrtSeason>[];
  for (final item in lrtJsonObjects(raw)) {
    final slug = lrtSeasonSlugOf(lrtString(item['url']));
    final title = lrtString(item['title']);
    if (slug == null || title == null || !seen.add(slug)) continue;
    seasons.add(LrtSeason(id: lrtString(item['id']) ?? slug, title: title, slug: slug));
  }
  return seasons;
}

LrtRecording? _episode(Map<String, dynamic> item) {
  final postId = lrtPostIdOf(lrtString(item['url']));
  final title = lrtString(item['title']);
  if (postId == null || title == null) return null;
  final category = item['category'];
  final season = item['season'];
  return LrtRecording(
    postId: postId,
    title: title,
    imageTemplate: _picture(item['image']),
    published: lrtParseIso(item['date']),
    durationSeconds: lrtParseDuration(item['duration']),
    showTitle: category is Map<String, dynamic> ? lrtString(category['title']) : null,
    showSlug: category is Map<String, dynamic> ? lrtShowSlugOf(lrtString(category['url'])) : null,
    seasonSlug: season is Map<String, dynamic> ? lrtSeasonSlugOf(lrtString(season['url'])) : null,
    ageRating: lrtString(item['ageRestricted']),
  );
}

String? _picture(Object? image) =>
    image is Map<String, dynamic> ? lrtImageTemplateFromParts(image['prefix'], image['postfix']) : null;

String? _summary(Object? description) {
  final text = htmlToText(lrtString(description));
  return text.isEmpty ? null : text;
}
