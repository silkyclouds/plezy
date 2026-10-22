import 'lrt_dates.dart';
import 'lrt_images.dart';
import 'lrt_json.dart';
import 'lrt_models.dart';
import 'lrt_refs.dart';

/// Hits per page, fixed by the site.
const lrtSearchPageSize = 10;

/// Reads a search answer. Audio, photo and Epika (separate service) hits are left out. Programme-level hits come from
/// `similar_categories`, and borrow the picture of a recording of the same programme.
LrtSearchPage parseLrtSearch(Object? body) {
  final json = lrtJsonObject(body);
  if (json == null) return LrtSearchPage.empty;
  final items = lrtJsonObjects(json['items']);
  final photos = <int, String>{};
  final recordings = <LrtRecording>[];
  for (final item in items) {
    final recording = _recording(item);
    if (recording == null) continue;
    recordings.add(recording);
    final category = lrtInt(item['category_id']);
    final photo = recording.imageTemplate;
    if (category != null && photo != null) photos.putIfAbsent(category, () => photo);
  }
  return LrtSearchPage(
    total: lrtInt(json['total_found']) ?? recordings.length,
    recordings: recordings,
    programmes: _programmes(json['similar_categories'], photos),
  );
}

LrtRecording? _recording(Map<String, dynamic> item) {
  final postId = lrtPostIdOf(lrtString(item['url']));
  final title = lrtString(item['title']);
  if (postId == null || title == null) return null;
  if (_isNotVideo(item) || _flag(item['is_audio']) || _flag(item['is_epika'])) return null;
  final seasonUrl = lrtString(item['season_url']);
  return LrtRecording(
    postId: postId,
    title: title,
    subtitle: lrtString(item['subtitle']),
    imageTemplate: lrtImageTemplate(lrtString(item['photo'])),
    published: lrtParseIso(item['item_date_iso8601']),
    showTitle: lrtString(item['category_title']),
    showSlug: lrtShowSlugOf(seasonUrl),
    seasonSlug: lrtSeasonSlugOf(seasonUrl),
    ageRating: lrtString(item['age_restriction']),
    isMovie: _flag(item['is_movie']),
  );
}

List<LrtProgramme> _programmes(Object? raw, Map<int, String> photos) {
  final seen = <String>{};
  final programmes = <LrtProgramme>[];
  for (final item in lrtJsonObjects(raw)) {
    final slug = lrtShowSlugOf(lrtString(item['url']));
    final title = lrtString(item['category_title']);
    if (slug == null || title == null || _isNotVideo(item) || !seen.add(slug)) continue;
    final id = lrtInt(item['category_id']);
    programmes.add(LrtProgramme(slug: slug, title: title, imageTemplate: id == null ? null : photos[id]));
  }
  return programmes;
}

bool _isNotVideo(Map<String, dynamic> item) => item['is_video'] != null && !_flag(item['is_video']);

bool _flag(Object? value) => value == true || (value is num && value != 0) || value == '1';
