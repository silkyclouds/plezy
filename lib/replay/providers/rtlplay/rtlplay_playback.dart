import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

const _watchOnTheSite = 'https://www.rtlplay.be/';

/// RTL Play only serves streams to a signed-in viewer.
ReplayPlayback rtlPlayLoginRequired() => const ReplayPlayback.unavailable(
  ReplayAvailability.loginRequired,
  message: 'RTL Play streams need a free RTL account. Sign in to continue, or watch at $_watchOnTheSite',
);

/// A show or season has no stream of its own.
ReplayPlayback rtlPlayNotPlayable() => const ReplayPlayback.unavailable(ReplayAvailability.unknown);

/// The programme or episode is no longer listed, which is how the catalogue expires content.
ReplayPlayback rtlPlayGone() => const ReplayPlayback.unavailable(
  ReplayAvailability.expired,
  message: 'This programme is no longer available on RTL Play',
);
