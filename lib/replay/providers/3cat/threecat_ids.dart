import '../../model/replay_ref.dart';

const threeCatSourceId = '3cat';

/// Season key of the episodes that belong to no numbered season.
const threeCatLooseSeason = '_all';

ReplayRef threeCatShowRef(String programmeId) => ReplayRef(threeCatSourceId, 'p$programmeId');

ReplayRef threeCatSeasonRef(String programmeId, String seasonKey) =>
    ReplayRef(threeCatSourceId, 'p$programmeId/$seasonKey');

ReplayRef threeCatVideoRef(String videoId) => ReplayRef(threeCatSourceId, 'v$videoId');

/// What a `3cat` ref points at. Native ids are `p<programme>`, `p<programme>/<season key>` and `v<video>`.
sealed class ThreeCatTarget {
  const ThreeCatTarget();
}

class ThreeCatShowTarget extends ThreeCatTarget {
  final String programmeId;

  const ThreeCatShowTarget(this.programmeId);
}

class ThreeCatSeasonTarget extends ThreeCatTarget {
  final String programmeId;
  final String seasonKey;

  const ThreeCatSeasonTarget(this.programmeId, this.seasonKey);
}

class ThreeCatVideoTarget extends ThreeCatTarget {
  final String videoId;

  const ThreeCatVideoTarget(this.videoId);
}

final _digits = RegExp(r'^\d+$');

ThreeCatTarget? parseThreeCatRef(ReplayRef ref) {
  if (ref.source != threeCatSourceId || ref.nativeId.length < 2) return null;
  final body = ref.nativeId.substring(1);
  switch (ref.nativeId[0]) {
    case 'v':
      return _digits.hasMatch(body) ? ThreeCatVideoTarget(body) : null;
    case 'p':
      final cut = body.indexOf('/');
      final programme = cut < 0 ? body : body.substring(0, cut);
      if (!_digits.hasMatch(programme)) return null;
      if (cut < 0) return ThreeCatShowTarget(programme);
      final key = body.substring(cut + 1);
      return key.isEmpty ? null : ThreeCatSeasonTarget(programme, key);
  }
  return null;
}
