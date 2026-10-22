import '../../model/replay_ref.dart';

const nfbSourceId = 'nfb';

/// Native ids: a film or episode is its slug, a show is `s/{slug}` and a season is `s/{slug}/{number}`.
/// Film slugs never contain a slash, so the prefix cannot collide with one.
const _showPrefix = 's/';

ReplayRef nfbRef(String nativeId) => ReplayRef(nfbSourceId, nativeId);

ReplayRef nfbShowRef(String slug) => nfbRef('$_showPrefix$slug');

ReplayRef nfbSeasonRef(String slug, int number) => nfbRef('$_showPrefix$slug/$number');

/// Where a native id points inside a series, or null for a film or episode.
typedef NfbSeriesTarget = ({String slug, int? season});

NfbSeriesTarget? parseNfbSeriesId(String nativeId) {
  if (!nativeId.startsWith(_showPrefix)) return null;
  final parts = nativeId.substring(_showPrefix.length).split('/');
  final slug = parts.first;
  if (slug.isEmpty || parts.length > 2) return null;
  if (parts.length == 1) return (slug: slug, season: null);
  final season = int.tryParse(parts[1]);
  return season == null ? null : (slug: slug, season: season);
}

/// The slug in the last path segment of a film, episode or series address.
String? nfbSlugFromUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList();
  return segments == null || segments.isEmpty ? null : segments.last;
}

/// The series slug in a `/series/{slug}/...` address.
String? nfbSeriesSlugFromUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments == null) return null;
  final at = segments.indexOf('series');
  return at >= 0 && at + 1 < segments.length ? segments[at + 1] : null;
}
