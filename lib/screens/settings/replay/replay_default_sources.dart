import '../../../replay/provider/replay_source_info.dart';

/// The channels switched on when the viewer first opens catch-up TV: those of the viewer's own country, plus any other
/// channel that plays from there. Without a known country everything is on, since nothing is greyed out on a guess.
Set<String> defaultReplaySources(Iterable<ReplaySourceInfo> infos, String? viewerCountry) => {
  for (final info in infos)
    if (viewerCountry == null || info.country == viewerCountry || !info.restrictsViewerIn(viewerCountry)) info.id,
};
