import '../../text/html_text.dart';
import 'lrt_dates.dart';
import 'lrt_images.dart';
import 'lrt_json.dart';
import 'lrt_models.dart';
import 'lrt_refs.dart';

/// Reads the metadata record of one recording. Returns null when the body is not a record.
LrtRecording? parseLrtArticle(Object? body, {required String postId}) {
  final json = lrtJsonObject(body);
  final title = lrtString(json?['title']);
  if (json == null || title == null) return null;
  final category = json['category'];
  final season = json['season'];
  final image = json['image'];
  final summary = htmlToText(lrtString(json['description']) ?? lrtString(json['content']));
  return LrtRecording(
    postId: lrtPostIdOf(lrtString(json['url'])) ?? postId,
    title: title,
    summary: summary.isEmpty ? null : summary,
    imageTemplate: image is Map<String, dynamic> ? lrtImageTemplateFromParts(image['prefix'], image['postfix']) : null,
    published: lrtParseIso(json['date']),
    durationSeconds: lrtParseDuration(json['duration']),
    showTitle: category is Map<String, dynamic> ? lrtString(category['title']) : null,
    showSlug: category is Map<String, dynamic> ? lrtShowSlugOf(lrtString(category['url'])) : null,
    seasonSlug: season is Map<String, dynamic> ? lrtSeasonSlugOf(lrtString(season['url'])) : null,
    ageRating: lrtString(json['ageRestricted']),
    availableUntil: lrtParseIso(json['validTill']),
  );
}
