import 'dart:collection';

import '../model/replay_ref.dart';

/// The pictures a title was last seen with.
class ReplayArtwork {
  final String? poster;
  final String? backdrop;

  const ReplayArtwork({this.poster, this.backdrop});
}

/// Remembers the artwork of titles seen in lists, so a title page that arrives without any (broadcaster pages often
/// carry less than their listings) still shows the picture the viewer just clicked on.
class ReplayArtworkMemory {
  static const _capacity = 2000;
  final LinkedHashMap<String, ReplayArtwork> _seen = LinkedHashMap();

  ReplayArtwork? recall(ReplayRef ref) => _seen[ref.toString()];

  void remember(ReplayRef ref, ReplayArtwork artwork) {
    final key = ref.toString();
    _seen.remove(key);
    _seen[key] = artwork;
    if (_seen.length > _capacity) _seen.remove(_seen.keys.first);
  }
}
