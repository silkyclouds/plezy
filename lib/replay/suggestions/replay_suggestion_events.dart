import 'package:flutter/foundation.dart';

/// Bumped whenever the viewer changes what the home screen offers from catch-up TV, so the home screen can rebuild
/// its rows. The value only changes; it carries no meaning.
final ValueNotifier<int> replaySuggestionsChanged = ValueNotifier<int>(0);

void notifyReplaySuggestionsChanged() => replaySuggestionsChanged.value++;
