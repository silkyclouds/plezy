import 'dart:collection';

import '../model/replay_title.dart';

/// Remembers titles seen in lists, so a title page that arrives without pictures, show or season (broadcaster pages
/// often carry less than their listings) still shows what the viewer just clicked on and downloads under its show.
class ReplayTitleMemory {
  static const _capacity = 2000;
  final LinkedHashMap<String, ReplayTitle> _seen = LinkedHashMap();

  /// [title] completed from what was seen of it before; it becomes the remembered record.
  ReplayTitle fill(ReplayTitle title) {
    final key = title.ref.toString();
    final earlier = _seen.remove(key);
    final merged = earlier == null ? title : title.filledFrom(earlier);
    _seen[key] = merged;
    if (_seen.length > _capacity) _seen.remove(_seen.keys.first);
    return merged;
  }
}
