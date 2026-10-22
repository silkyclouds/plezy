import 'package:flutter/material.dart';

import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../replay/client/replay_accounts.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../settings/replay/replay_sign_in_dialog.dart';
import 'replay_blocking.dart';
import 'replay_client_lookup.dart';
import 'replay_open_settings.dart';
import 'replay_unavailable_dialog.dart';
import 'replay_unavailable_texts.dart';

/// Decides whether playback of [item] may start. A catch-up title that cannot be played here gets an explanation in
/// place of the player; signing in from that dialog lets playback go on.
///
/// Returns true when the caller should start playback, false when it must not.
Future<bool> replayAllowsPlayback(BuildContext context, MediaItem item) async {
  final client = replayClientFor(context, item);
  if (!replayItemBlocks(item, replaySignedInOf(client))) return true;
  final locale = LocaleSettings.currentLocale;
  final texts = replayUnavailableTexts(
    item,
    place: replayPlaceOf(client),
    language: locale.languageCode,
    intlLocale: locale.intlLocaleName,
  );
  if (texts == null) return true;
  final choice = await showReplayUnavailableDialog(context, texts, canSignIn: replayCanSignIn(client, item));
  if (!context.mounted) return false;
  switch (choice) {
    case ReplayUnavailableChoice.changeLocation:
      await openReplayLocationSettings(context);
      return false;
    case ReplayUnavailableChoice.signIn:
      return _signIn(context, item, client?.accounts);
    case ReplayUnavailableChoice.close || null:
      return false;
  }
}

Future<bool> _signIn(BuildContext context, MediaItem item, ReplayAccounts? accounts) async {
  final info = replaySourceInfo(replaySourceIdOf(item) ?? '');
  if (accounts == null || info == null) return false;
  return showReplaySignIn(context, accounts: accounts, info: info);
}
