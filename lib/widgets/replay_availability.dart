import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../replay/mapping/replay_mapper.dart';
import '../replay/model/replay_title.dart';
import 'app_icon.dart';

/// The state worth telling the viewer about, or null when the title can be played (or nothing is known).
ReplayAvailability? _unplayable(Object item) {
  if (item is! MediaItem || !item.backend.isReplay) return null;
  final availability = replayAvailabilityOf(item);
  return availability == ReplayAvailability.playable || availability == ReplayAvailability.unknown
      ? null
      : availability;
}

/// Greys out the artwork of a catch-up title that cannot be played here. The picture stays recognisable.
class ReplayAvailabilityShade extends StatelessWidget {
  final Object item;
  final Widget child;

  const ReplayAvailabilityShade({super.key, required this.item, required this.child});

  /// Keeps 20 % of the colour: enough to recognise the cover, little enough to read as unavailable.
  static const _desaturate = ColorFilter.matrix(<double>[
    0.4, 0.55, 0.05, 0, 0, //
    0.2, 0.75, 0.05, 0, 0, //
    0.2, 0.55, 0.25, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (_unplayable(item) == null) return child;
    return Opacity(
      opacity: 0.55,
      child: ColorFiltered(colorFilter: _desaturate, child: child),
    );
  }
}

/// The small pictogram on the corner of an unplayable catch-up title, with the reason as its label.
class ReplayAvailabilityBadge extends StatelessWidget {
  final Object item;

  const ReplayAvailabilityBadge({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final availability = _unplayable(item);
    if (availability == null) return const SizedBox.shrink();
    final (icon, label) = _describe(availability);
    return Positioned(
      left: 6,
      bottom: 6,
      child: Semantics(
        label: label,
        child: Tooltip(
          message: label,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: AppIcon(icon, fill: 1, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  (IconData, String) _describe(ReplayAvailability availability) => switch (availability) {
    ReplayAvailability.geoBlocked => (Symbols.public_off_rounded, t.replay.availability.geoBlocked),
    ReplayAvailability.drmProtected => (Symbols.lock_rounded, t.replay.availability.drm),
    ReplayAvailability.loginRequired => (Symbols.login_rounded, t.replay.availability.loginRequired),
    ReplayAvailability.expired => (Symbols.event_busy_rounded, t.replay.availability.expired),
    ReplayAvailability.upcoming => (Symbols.schedule_rounded, t.replay.availability.upcoming),
    ReplayAvailability.timeSlotRestricted => (Symbols.bedtime_rounded, t.replay.availability.timeSlot),
    ReplayAvailability.playable || ReplayAvailability.unknown => (Symbols.help_rounded, ''),
  };
}
