import 'package:flutter/widgets.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../replay/mapping/replay_mapper.dart';
import '../../replay/model/replay_title.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../replay/provider/replay_source_info.dart';
import '../../widgets/replay/replay_unavailable_reason.dart';
import 'replay_blocking.dart';
import 'replay_country_grammar.dart';
import 'replay_detail_dates.dart';

/// Where the viewer is according to the app, and whether they chose it themselves.
class ReplayViewerPlace {
  final String? country;
  final bool chosen;

  const ReplayViewerPlace({this.country, this.chosen = false});
}

/// Everything a screen says about one unavailable catch-up title: the pictogram, the one-line notice of the action
/// row, and the title and text of the dialog shown when the viewer tries to play it.
class ReplayUnavailableTexts {
  final ReplayAvailability availability;
  final IconData icon;
  final String notice;
  final String dialogTitle;
  final String dialogBody;

  const ReplayUnavailableTexts({
    required this.availability,
    required this.icon,
    required this.notice,
    required this.dialogTitle,
    required this.dialogBody,
  });

  bool get offersLocationChange => availability == ReplayAvailability.geoBlocked;
  bool get offersSignIn => availability == ReplayAvailability.loginRequired;
}

/// The texts for [item], or null when it can be played or is not a catch-up title.
ReplayUnavailableTexts? replayUnavailableTexts(
  MediaItem item, {
  required ReplayViewerPlace place,
  required String language,
  required String intlLocale,
}) {
  final reason = replayUnavailableReasonOf(item);
  if (reason == null) return null;
  final sourceId = replaySourceIdOf(item) ?? '';
  final channel = item.studio ?? replaySourceName(sourceId);
  final what = _Wording.of(item);
  final dates = replayDatesOf(item);
  String withYear(DateTime d) => replayDateWithYear(d, intlLocale: intlLocale);
  String day(DateTime d) => replayDateWithoutYear(d, intlLocale: intlLocale);
  String time(DateTime d) => replayTimeOfDay(d, language: language, intlLocale: intlLocale);
  final until = dates.availableUntil;
  final airs = dates.airsAt;
  final texts = t.replay.detail;

  ReplayUnavailableTexts build(String notice, String title, String body) => ReplayUnavailableTexts(
    availability: reason.availability,
    icon: reason.icon,
    notice: notice,
    dialogTitle: title,
    dialogBody: body,
  );

  return switch (reason.availability) {
    ReplayAvailability.geoBlocked => build(
      _geoNotice(reason.shortReason, place, language),
      reason.shortReason,
      _geoBody(item, channel: channel, what: what, place: place, language: language),
    ),
    ReplayAvailability.drmProtected => build(
      texts.notice.drm,
      texts.dialog.drmTitle,
      texts.dialog.drm(channel: channel, what: what.phrase, pronoun: what.pronoun),
    ),
    ReplayAvailability.loginRequired => build(
      texts.dialog.loginTitle(channel: channel),
      texts.dialog.loginTitle(channel: channel),
      texts.dialog.login(what: what.phrase),
    ),
    ReplayAvailability.expired => build(
      until == null ? texts.notice.expired : texts.notice.expiredOn(date: withYear(until)),
      texts.dialog.expiredTitle,
      until == null
          ? texts.dialog.expiredUndated(channel: channel, what: what.phrase)
          : texts.dialog.expired(channel: channel, what: what.phrase, date: withYear(until)),
    ),
    ReplayAvailability.upcoming => build(
      airs == null ? texts.notice.upcoming : texts.notice.upcomingAt(date: day(airs), time: time(airs)),
      airs == null ? texts.dialog.upcomingTitleUndated : texts.dialog.upcomingTitle(date: day(airs), time: time(airs)),
      airs == null
          ? texts.dialog.upcomingUndated(channel: channel, what: what.phrase)
          : texts.dialog.upcoming(channel: channel, what: what.phrase),
    ),
    _ => build(texts.notice.timeSlot, texts.dialog.timeSlotTitle, texts.dialog.timeSlot(channel: channel)),
  };
}

String _geoNotice(String reason, ReplayViewerPlace place, String language) {
  final country = place.country;
  if (country == null) return t.replay.detail.notice.geo(reason: reason);
  return t.replay.detail.notice.geoLocated(reason: reason, location: replayInCountry(country, language));
}

String _geoBody(
  MediaItem item, {
  required String channel,
  required _Wording what,
  required ReplayViewerPlace place,
  required String language,
}) {
  final dialog = t.replay.detail.dialog;
  final home = replaySourceInfo(replaySourceIdOf(item) ?? '')?.country;
  final blocked = home == null || home == replayInternational
      ? dialog.geoBlockedHere(channel: channel, what: what.phrase)
      : dialog.geoBlocked(channel: channel, what: what.phrase, outside: replayOutsideCountry(home, language));
  final country = place.country;
  if (country == null) return blocked;
  final location = replayInCountry(country, language);
  final basis = place.chosen
      ? dialog.placedByChoice(location: location)
      : dialog.placedByConnection(location: location);
  return '$blocked $basis';
}

/// "this episode" or "this video", with the pronoun that replaces it in the same language.
class _Wording {
  final String phrase;
  final String pronoun;

  const _Wording(this.phrase, this.pronoun);

  factory _Wording.of(MediaItem item) {
    final kind = t.replay.detail.kind;
    return item.isEpisode ? _Wording(kind.episode, kind.episodePronoun) : _Wording(kind.video, kind.videoPronoun);
  }
}
