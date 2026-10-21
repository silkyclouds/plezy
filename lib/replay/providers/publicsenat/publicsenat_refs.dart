import '../../model/replay_ref.dart';
import '../dailymotion/dailymotion_ids.dart';

const publicSenatSourceId = 'publicsenat';

/// A show is `slug`, a season is `slug/s<startYear>` and an episode is `slug/<dailymotion id>`.
ReplayRef publicSenatShowRef(String slug) => ReplayRef(publicSenatSourceId, slug);

ReplayRef publicSenatSeasonRef(String slug, int startYear) => ReplayRef(publicSenatSourceId, '$slug/s$startYear');

ReplayRef publicSenatEpisodeRef(String slug, String videoId) => ReplayRef(publicSenatSourceId, '$slug/$videoId');

/// What a native id points at. Exactly one of [seasonStartYear] and [videoId] is set for seasons and
/// episodes; both are null for a show.
class PublicSenatTarget {
  final String slug;
  final int? seasonStartYear;
  final String? videoId;

  const PublicSenatTarget(this.slug, {this.seasonStartYear, this.videoId});

  bool get isShow => seasonStartYear == null && videoId == null;
}

final _seasonPart = RegExp(r'^s(\d{4})$');

/// Parses a native id built by the functions above, or returns null for anything else.
PublicSenatTarget? parsePublicSenatId(String nativeId) {
  final cut = nativeId.indexOf('/');
  if (cut < 0) return nativeId.isEmpty ? null : PublicSenatTarget(nativeId);
  final slug = nativeId.substring(0, cut);
  final rest = nativeId.substring(cut + 1);
  if (slug.isEmpty) return null;
  final season = _seasonPart.firstMatch(rest);
  if (season != null) return PublicSenatTarget(slug, seasonStartYear: int.parse(season.group(1)!));
  if (isDailymotionVideoId(rest)) return PublicSenatTarget(slug, videoId: rest);
  return null;
}
