import '../../model/replay_title.dart';
import 'nhkworld_numbering.dart';

/// Whether an item's `video` block can be played at [now]. The catalogue drops expired items or empties their
/// `url`, and gives no geographic signal, so the window and the presence of a stream are all there is to judge by.
ReplayAvailability nhkAvailability(Object? video, DateTime now) {
  if (video is! Map) return ReplayAvailability.expired;
  final expires = nhkParseDate(video['expired_at']);
  if (expires != null && !expires.isAfter(now)) {
    return ReplayAvailability.expired;
  }
  final published = nhkParseDate(video['published_at']);
  if (published != null && published.isAfter(now)) {
    return ReplayAvailability.upcoming;
  }
  final url = video['url'];
  return url is String && url.isNotEmpty ? ReplayAvailability.playable : ReplayAvailability.expired;
}
