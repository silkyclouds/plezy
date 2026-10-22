import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../replay/mapping/replay_mapper.dart';
import '../../replay/model/replay_ref.dart';
import '../../replay/model/replay_title.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../replay/provider/replay_source_info.dart';
import 'replay_country_phrase.dart';

/// Why a catch-up title cannot be played from here: the pictogram that stands for the case and the reason in a few
/// words. One value per card, list row and hero, so every surface says the same thing.
class ReplayUnavailableReason {
  final ReplayAvailability availability;
  final IconData icon;
  final String shortReason;

  const ReplayUnavailableReason({required this.availability, required this.icon, required this.shortReason});
}

/// The reason [item] is unplayable, or null for a playable title, a non-catch-up item and an unknown state.
ReplayUnavailableReason? replayUnavailableReasonOf(Object item) {
  if (item is! MediaItem || !item.backend.isReplay) return null;
  final availability = replayAvailabilityOf(item);
  final icon = switch (availability) {
    ReplayAvailability.geoBlocked => Symbols.public_off_rounded,
    ReplayAvailability.drmProtected => Symbols.lock_rounded,
    ReplayAvailability.loginRequired => Symbols.account_circle_rounded,
    ReplayAvailability.expired => Symbols.event_busy_rounded,
    ReplayAvailability.upcoming => Symbols.event_upcoming_rounded,
    ReplayAvailability.timeSlotRestricted => Symbols.schedule_rounded,
    ReplayAvailability.playable || ReplayAvailability.unknown => null,
  };
  if (icon == null) return null;
  return ReplayUnavailableReason(availability: availability, icon: icon, shortReason: _shortReason(item, availability));
}

String _shortReason(MediaItem item, ReplayAvailability availability) {
  final dates = replayDatesOf(item);
  return switch (availability) {
    ReplayAvailability.geoBlocked => _geoReason(item),
    ReplayAvailability.drmProtected => t.replay.cards.drm,
    ReplayAvailability.loginRequired => t.replay.cards.loginRequired,
    ReplayAvailability.expired =>
      dates.availableUntil == null
          ? t.replay.cards.expired
          : t.replay.cards.expiredOn(date: _shortDate(dates.availableUntil!)),
    ReplayAvailability.upcoming =>
      dates.airsAt == null
          ? t.replay.cards.upcoming
          : t.replay.cards.upcomingAt(date: _shortDate(dates.airsAt!), time: _shortTime(dates.airsAt!)),
    _ => t.replay.cards.timeSlot,
  };
}

/// The country the broadcaster reserves the title for, or the generic wording when it has no single home country.
String _geoReason(MediaItem item) {
  final ref = ReplayRef.tryParse(item.id);
  final country = ref == null ? null : replaySourceInfo(ref.source)?.country;
  if (country == null || country == replayInternational) return t.replay.availability.geoBlocked;
  return t.replay.cards.onlyIn(country: replayCountryPhrase(country, LocaleSettings.currentLocale.languageCode));
}

String _shortDate(DateTime date) => DateFormat.MMMd(LocaleSettings.currentLocale.intlLocaleName).format(date.toLocal());

/// French writes 20 h 55 and 22 h; other languages use the locale's own time format.
String _shortTime(DateTime date) {
  final local = date.toLocal();
  if (LocaleSettings.currentLocale.languageCode != 'fr') {
    return DateFormat.jm(LocaleSettings.currentLocale.intlLocaleName).format(local);
  }
  return local.minute == 0 ? '${local.hour} h' : '${local.hour} h ${local.minute.toString().padLeft(2, '0')}';
}
