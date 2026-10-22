import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'nfb_page_data.dart';
import 'nfb_values.dart';

/// Reads a player page. Playable films hand over a signed HLS address; a film that cannot be watched here gets a
/// player page without one that says why.
///
/// The address expires after about half a day, so the result is used at once and never stored.
ReplayPlayback nfbParsePlayback(String html) {
  final options = nfbPlayerOptions(html);
  final main = _stream(options?['source'], _label(options));
  if (main != null) {
    final description = _stream(options?['dvSource'], 'AD');
    return ReplayPlayback(availability: ReplayAvailability.playable, streams: [main, ?description]);
  }
  return _withoutPlayer(nfbOverlayNotice(html));
}

ReplayPlayback _withoutPlayer(NfbOverlayNotice notice) {
  if (notice.messageId == 'MESSAGE_GEOBLOCKED') {
    return ReplayPlayback.unavailable(
      ReplayAvailability.geoBlocked,
      message: notice.message ?? 'This film is not available for free viewing in your location.',
    );
  }
  if (notice.offers.contains('BUY') || notice.offers.contains('RENT')) {
    return const ReplayPlayback.unavailable(
      ReplayAvailability.unknown,
      message: 'This film can only be bought or rented on nfb.ca.',
    );
  }
  return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: notice.message);
}

ReplayStream? _stream(Object? address, String label) {
  final url = nfbNonEmpty(address);
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
  return ReplayStream(url: uri.removeFragment(), label: label);
}

String _label(Map<String, dynamic>? options) => nfbNonEmpty(options?['language'])?.toUpperCase() ?? 'NFB';
