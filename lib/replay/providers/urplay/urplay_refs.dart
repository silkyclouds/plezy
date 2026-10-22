import '../../model/replay_ref.dart';

const urplaySourceId = 'urplay';

/// A UR series is one season of a show, so a show is named after one of its series ids.
ReplayRef urplayShowRef(String seriesId) => ReplayRef(urplaySourceId, 'show/$seriesId');

/// A season ref carries the show it was listed under, so an episode can find its way back without a search.
ReplayRef urplaySeasonRef(String showId, String seriesId) => ReplayRef(urplaySourceId, 'season/$showId/$seriesId');

ReplayRef urplayProgramRef(String programId) => ReplayRef(urplaySourceId, programId);

/// What a native id of this source points at.
sealed class UrTarget {
  const UrTarget();

  /// Parses the native id of a ref, or null when it is none of the three shapes this provider issues.
  static UrTarget? parse(ReplayRef ref) {
    if (ref.source != urplaySourceId) return null;
    final parts = ref.nativeId.split('/');
    return switch (parts) {
      ['show', final id] when _isId(id) => UrShow(id),
      ['season', final showId, final seriesId] when _isId(showId) && _isId(seriesId) => UrSeason(showId, seriesId),
      [final id] when _isId(id) => UrProgram(id),
      _ => null,
    };
  }

  static bool _isId(String value) => RegExp(r'^\d+$').hasMatch(value);
}

class UrShow extends UrTarget {
  final String seriesId;

  const UrShow(this.seriesId);
}

class UrSeason extends UrTarget {
  final String showId;
  final String seriesId;

  const UrSeason(this.showId, this.seriesId);
}

class UrProgram extends UrTarget {
  final String programId;

  const UrProgram(this.programId);
}
