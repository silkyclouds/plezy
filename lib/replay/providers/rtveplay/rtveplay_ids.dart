import '../../model/replay_ref.dart';

const rtveSourceId = 'rtveplay';

/// Native id of the season that stands for "every episode" of a programme without real seasons.
const rtveAllEpisodesSeason = '_all';

/// What a native id of this source points at. Programme and video ids are both plain numbers on RTVE's side, so
/// native ids carry a prefix: `p123` is a programme, `p123/456` one of its seasons, `v789` a video.
sealed class RtveTarget {
  const RtveTarget();
}

class RtveShowTarget extends RtveTarget {
  final String programId;

  const RtveShowTarget(this.programId);
}

class RtveSeasonTarget extends RtveTarget {
  final String programId;

  /// A numeric season id, or [rtveAllEpisodesSeason].
  final String seasonId;

  const RtveSeasonTarget(this.programId, this.seasonId);

  bool get isSynthetic => seasonId == rtveAllEpisodesSeason;
}

class RtveVideoTarget extends RtveTarget {
  final String videoId;

  const RtveVideoTarget(this.videoId);
}

ReplayRef rtveShowRef(String programId) => ReplayRef(rtveSourceId, 'p$programId');

ReplayRef rtveSeasonRef(String programId, String seasonId) => ReplayRef(rtveSourceId, 'p$programId/$seasonId');

ReplayRef rtveVideoRef(String videoId) => ReplayRef(rtveSourceId, 'v$videoId');

final _show = RegExp(r'^p(\d+)$');
final _season = RegExp(r'^p(\d+)/(\d+|' + rtveAllEpisodesSeason + r')$');
final _video = RegExp(r'^v(\d+)$');

/// The target of [ref], or null when the id is not one this provider issues.
RtveTarget? parseRtveRef(ReplayRef ref) {
  if (ref.source != rtveSourceId) return null;
  final id = ref.nativeId;
  if (_show.firstMatch(id) case final m?) return RtveShowTarget(m.group(1)!);
  if (_season.firstMatch(id) case final m?) return RtveSeasonTarget(m.group(1)!, m.group(2)!);
  if (_video.firstMatch(id) case final m?) return RtveVideoTarget(m.group(1)!);
  return null;
}
