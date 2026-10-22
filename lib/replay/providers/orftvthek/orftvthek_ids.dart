import '../../model/replay_ref.dart';

/// Provider id, ref prefix and logo slug of ORF ON.
const orfSourceId = 'orftvthek';

/// Key of the season that holds every episode of a show that has no real seasons.
const orfAllEpisodes = 'all';

/// Key of the season that holds the episodes a numbered show lists without any season marker.
const orfExtras = 'extras';

/// Ref of a stand-alone programme or one episode of a show.
ReplayRef orfEpisodeRef(int id) => ReplayRef(orfSourceId, 'episode/$id');

/// Ref of a clip cut out of a programme.
ReplayRef orfSegmentRef(int id) => ReplayRef(orfSourceId, 'segment/$id');

/// Ref of a show that is exactly one ORF profile.
ReplayRef orfProfileRef(int id) => ReplayRef(orfSourceId, 'profile/$id');

/// Ref of a show whose seasons ORF publishes as separate profiles ("Kiwi Staffel 1", "Kiwi Staffel 2").
ReplayRef orfSeriesRef(String key) => ReplayRef(orfSourceId, 'series/$key');

/// Ref of one season. [key] is `s<number>`, `y<year>`, [orfExtras] or [orfAllEpisodes].
ReplayRef orfSeasonRef(int profileId, String key) => ReplayRef(orfSourceId, 'season/$profileId/$key');

String orfNumberedSeasonKey(int number) => 's$number';

String orfYearSeasonKey(int year) => 'y$year';

/// What a native id points at.
sealed class OrfTarget {
  const OrfTarget();
}

class OrfEpisodeTarget extends OrfTarget {
  final int id;

  const OrfEpisodeTarget(this.id);
}

class OrfSegmentTarget extends OrfTarget {
  final int id;

  const OrfSegmentTarget(this.id);
}

class OrfProfileTarget extends OrfTarget {
  final int id;

  const OrfProfileTarget(this.id);
}

class OrfSeriesTarget extends OrfTarget {
  final String key;

  const OrfSeriesTarget(this.key);
}

class OrfSeasonTarget extends OrfTarget {
  final int profileId;
  final String key;

  const OrfSeasonTarget(this.profileId, this.key);
}

/// Reads a native id built by the functions above, or null when it is none of them.
OrfTarget? parseOrfRef(ReplayRef ref) {
  final parts = ref.nativeId.split('/');
  if (parts.length < 2 || parts.any((part) => part.isEmpty)) return null;
  final id = int.tryParse(parts[1]);
  return switch ((parts[0], parts.length)) {
    ('episode', 2) when id != null => OrfEpisodeTarget(id),
    ('segment', 2) when id != null => OrfSegmentTarget(id),
    ('profile', 2) when id != null => OrfProfileTarget(id),
    ('series', 2) => OrfSeriesTarget(parts[1]),
    ('season', 3) when id != null => OrfSeasonTarget(id, parts[2]),
    _ => null,
  };
}
