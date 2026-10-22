import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'drtv_access.dart';

const _home = 'DK';

/// Which of [titles] a viewer in [country] cannot watch, judged from the flags the catalogue gave each one.
///
/// DRM shows are protected for everyone, so they are reported for any country, and before the country rule: that is
/// the block that stays when the viewer moves. Titles with no flags on record, and titles the viewer can watch, are
/// left out of the answer.
Map<ReplayRef, ReplayAvailability> drtvPredictAvailability(
  DrtvAccessBook book,
  Iterable<ReplayTitle> titles,
  String country,
) {
  final abroad = country.toUpperCase() != _home;
  final verdicts = <ReplayRef, ReplayAvailability>{};
  for (final title in titles) {
    final access = book.of(title.ref);
    if (access == null) continue;
    if (access.drm) {
      verdicts[title.ref] = ReplayAvailability.drmProtected;
    } else if (access.denmarkOnly && abroad) {
      verdicts[title.ref] = ReplayAvailability.geoBlocked;
    }
  }
  return verdicts;
}
