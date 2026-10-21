import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'm6plus_assets.dart';
import 'm6plus_availability.dart';
import 'm6plus_geo.dart';

/// What the stream list of a video allows, before any manifest is requested.
class M6plusPlaybackPlan {
  /// Set when nothing can be played; [candidates] is then empty.
  final ReplayPlayback? verdict;

  /// Clear streams, best first.
  final List<M6plusAsset> candidates;
  final ReplayCredits? credits;

  const M6plusPlaybackPlan({this.verdict, this.candidates = const [], this.credits});

  /// The result once the first candidate has been confirmed reachable.
  ReplayPlayback get playback => ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [for (final a in candidates) ReplayStream(url: a.url, label: _label(a))],
    credits: credits,
  );
}

/// Chooses clear streams for [video], or the reason there are none. Protected streams are never offered.
M6plusPlaybackPlan m6plusPlanPlayback(Map<String, dynamic> video, {String? country, DateTime? now}) {
  final availability = m6plusVideoAvailability(video, country: country, now: now);
  if (availability != ReplayAvailability.playable) {
    return M6plusPlaybackPlan(
      verdict: ReplayPlayback.unavailable(availability, message: _message(video, availability, country)),
    );
  }
  return M6plusPlaybackPlan(candidates: m6plusPlayableAssets(m6plusAssetsOf(video)), credits: _credits(video));
}

String? _message(Map<String, dynamic> video, ReplayAvailability availability, String? country) {
  if (availability != ReplayAvailability.geoBlocked || country == null) return m6plusUnavailableMessage(availability);
  final allowed = m6plusPlayableAssets(m6plusAssetsOf(video)).first.countries;
  return M6plusGeoBlock(country, allowed).message;
}

String _label(M6plusAsset asset) {
  if (asset.isAudio) return 'Audio';
  return asset.quality == 'hd' ? 'HD' : 'SD';
}

ReplayCredits? _credits(Map<String, dynamic> video) {
  final clips = video['clips'];
  final clip = clips is List && clips.isNotEmpty && clips.first is Map<String, dynamic> ? clips.first as Map : null;
  final start = (clip?['tc_ending_credits'] as num?)?.toDouble();
  final end = (video['duration'] is num ? video['duration'] as num : num.tryParse('${video['duration']}'))?.toDouble();
  if (start == null || end == null || start >= end) return null;
  return ReplayCredits(
    start: Duration(milliseconds: (start * 1000).round()),
    end: Duration(milliseconds: (end * 1000).round()),
  );
}
