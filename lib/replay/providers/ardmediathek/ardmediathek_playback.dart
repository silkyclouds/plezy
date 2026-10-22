import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'ardmediathek_item.dart';

/// Whether a CDN status for a stream means the viewer's country is refused. 403 is what the Akamai edge sends;
/// anything else, including no answer, is left to the player to report.
bool ardStatusRefusesCountry(int? status) => status == 403 || status == 451;

/// The playback for a page that offers streams: the German sound track, and the audio-described one next to it.
ReplayPlayback ardBuildPlayback(ArdItemFacts facts) {
  final main = facts.main;
  if (!facts.isPlayable || main == null) return ReplayPlayback.unavailable(facts.availability);
  final description = facts.audioDescription;
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [
      ReplayStream(url: main, label: 'DE'),
      if (description != null) ReplayStream(url: description, label: 'AD'),
    ],
    subtitles: facts.subtitles,
  );
}
