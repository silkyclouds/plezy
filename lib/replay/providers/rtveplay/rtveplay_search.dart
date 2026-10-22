import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtveplay_api.dart';
import 'rtveplay_mapper.dart';
import 'rtveplay_pages.dart';

/// Search results: matching programmes first, then matching full-length videos, without repeats.
///
/// RTVE's search also returns programmes that have nothing to watch, unlike the browse lists; they are kept because
/// the viewer asked for them by name.
class RtveSearch {
  final RtvePlayApi _api;
  final DateTime Function() _now;

  RtveSearch(this._api, this._now);

  Future<List<ReplayTitle>> search(String text) async {
    final found = await Future.wait([_api.searchPrograms(text), _api.searchContents(text)]);
    final seen = <ReplayRef>{};
    final titles = <ReplayTitle>[];
    for (final program in rtveItems(found[0])) {
      final show = rtveShowFromProgram(program);
      if (show != null && seen.add(show.ref)) titles.add(show);
    }
    for (final video in rtveItems(found[1])) {
      final episode = rtveTitleFromVideo(video, now: _now());
      if (episode != null && seen.add(episode.ref)) titles.add(episode);
    }
    return titles;
  }
}
