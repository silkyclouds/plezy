import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_title.dart';

import '../../test_helpers/media_items.dart';

/// A catch-up item stamped with [availability]; [stamps] adds the date stamps the mapper writes.
MediaItem replayItem(
  String id,
  ReplayAvailability availability, {
  MediaKind kind = MediaKind.episode,
  String? studio,
  String? clearLogoPath,
  Map<String, Object?> stamps = const {},
}) {
  return testMediaItem(
    id: id,
    backend: MediaBackend.replay,
    kind: kind,
    title: 'Titre',
    studio: studio,
    clearLogoPath: clearLogoPath,
    raw: {replayAvailabilityKey: availability.name, ...stamps},
  );
}
