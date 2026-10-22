import '../../model/replay_title.dart';

/// Reads the availability an item or chapter carries for the caller's connection.
///
/// `blockReason` is filled in for the requester's own IP address, which is why it is trusted over
/// `playableAbroad`: the latter is false for every Swiss-only item even when the caller is in Switzerland.
ReplayAvailability srgAvailability(Map<String, dynamic> item, DateTime now) {
  final reason = item['blockReason'] as String?;
  if (reason != null) return srgBlockReason(reason);
  final until = DateTime.tryParse(item['validTo'] as String? ?? '');
  if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
  final from = DateTime.tryParse(item['validFrom'] as String? ?? '');
  if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
  return ReplayAvailability.playable;
}

ReplayAvailability srgBlockReason(String reason) => switch (reason) {
  'GEOBLOCK' || 'VPNORPROXYDETECTED' => ReplayAvailability.geoBlocked,
  'STARTDATE' => ReplayAvailability.upcoming,
  'ENDDATE' => ReplayAvailability.expired,
  _ when reason.startsWith('AGERATING') => ReplayAvailability.timeSlotRestricted,
  _ => ReplayAvailability.unknown,
};
