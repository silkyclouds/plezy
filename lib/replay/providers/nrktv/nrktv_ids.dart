import '../../model/replay_ref.dart';

/// Provider id, ref prefix and logo slug of NRK TV.
const nrkSourceId = 'nrktv';

/// Season name of the stand-in season that holds the episodes of a series NRK does not split into seasons.
const nrkAllEpisodes = '_all';

/// Ref of a series, by its URL-friendly id.
ReplayRef nrkShowRef(String seriesId) => ReplayRef(nrkSourceId, 'series/$seriesId');

/// Ref of one season of a series, by the season's name (a number, a year, a year and month, or [nrkAllEpisodes]).
ReplayRef nrkSeasonRef(String seriesId, String season) => ReplayRef(nrkSourceId, 'series/$seriesId/$season');

/// Ref of a playable programme, by its program id.
ReplayRef nrkProgramRef(String programId) => ReplayRef(nrkSourceId, 'program/$programId');

/// What a native id points at. Program ids are not a fixed shape (some carry non-ASCII letters), so the id says it.
sealed class NrkTarget {
  const NrkTarget();
}

/// A series.
class NrkSeriesTarget extends NrkTarget {
  final String seriesId;

  const NrkSeriesTarget(this.seriesId);
}

/// One season of a series.
class NrkSeasonTarget extends NrkTarget {
  final String seriesId;
  final String season;

  const NrkSeasonTarget(this.seriesId, this.season);
}

/// An episode, film or clip.
class NrkProgramTarget extends NrkTarget {
  final String programId;

  const NrkProgramTarget(this.programId);
}

/// Reads a native id built by the functions above, or null when it is none of them.
NrkTarget? parseNrkRef(ReplayRef ref) {
  final parts = ref.nativeId.split('/');
  if (parts.length < 2 || parts.any((p) => p.isEmpty)) return null;
  return switch ((parts[0], parts.length)) {
    ('series', 2) => NrkSeriesTarget(parts[1]),
    ('series', 3) => NrkSeasonTarget(parts[1], parts[2]),
    ('program', 2) => NrkProgramTarget(parts[1]),
    _ => null,
  };
}
