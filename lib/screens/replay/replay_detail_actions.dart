import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_action_bar.dart';
import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../widgets/app_icon.dart';
import '../settings/replay/replay_palette.dart';
import '../settings/replay/replay_sign_in_dialog.dart';
import '../../replay/provider/replay_provider_registry.dart';
import 'replay_blocking.dart';
import 'replay_client_lookup.dart';
import 'replay_unavailable_texts.dart';

/// What the detail screen hands over to build the action row of a title that cannot be played.
class ReplayActionRowSpec {
  /// The show, season, episode or video the page describes, and the episodes loaded for it.
  final MediaItem page;
  final List<MediaItem> episodes;

  /// The node the screen sends focus to for its primary action; it moves to the first action that can take focus.
  final FocusNode primaryFocusNode;
  final double actionSize;
  final double tvScale;
  final bool isTv;

  /// The page's own watched and menu actions, kept as they are after the notice.
  final FocusableAction? watched;
  final FocusableAction? more;
  final VoidCallback onSignedIn;

  const ReplayActionRowSpec({
    required this.page,
    required this.episodes,
    required this.primaryFocusNode,
    required this.actionSize,
    required this.tvScale,
    required this.isTv,
    required this.onSignedIn,
    this.watched,
    this.more,
  });
}

/// Gap between the notice and the actions that stay after it.
const _noticeGap = 28.0;

/// The action row of a page whose title cannot be played, or null when the page keeps its usual row.
///
/// Play and Download give way to a line that says why, which cannot take focus. When the only thing missing is an
/// account, a Sign in button takes Play's place and its focus.
List<FocusableAction>? replayDetailActionRow(BuildContext context, ReplayActionRowSpec spec) {
  final client = replayClientFor(context, spec.page);
  final blocker = replayBlockerOf(spec.page, spec.episodes, replaySignedInOf(client));
  if (blocker == null) return null;
  final locale = LocaleSettings.currentLocale;
  final texts = replayUnavailableTexts(
    blocker,
    place: replayPlaceOf(client),
    language: locale.languageCode,
    intlLocale: locale.intlLocaleName,
  );
  if (texts == null) return null;
  final accounts = client?.accounts;
  final info = replaySourceInfo(replaySourceIdOf(blocker) ?? '');
  Future<bool> Function()? signIn;
  if (texts.offersSignIn && accounts != null && info != null && replayCanSignIn(client, blocker)) {
    signIn = () => showReplaySignIn(context, accounts: accounts, info: info);
  }
  return replayActionRow(spec, texts, signIn: signIn);
}

/// The row for a blocked title whose texts are known. [signIn] is given when the viewer can sign in to the channel;
/// it returns whether they ended up signed in.
List<FocusableAction> replayActionRow(
  ReplayActionRowSpec spec,
  ReplayUnavailableTexts texts, {
  Future<bool> Function()? signIn,
}) {
  if (signIn == null || !texts.offersSignIn) return _noticeRow(spec, texts);
  return [
    FocusableAction(
      debugLabel: 'detail_replay_sign_in',
      focusNode: spec.primaryFocusNode,
      onPressed: () async {
        if (await signIn()) spec.onSignedIn();
      },
      builder: (context, state) => _SignInButton(spec: spec, focused: state.showFocus),
    ),
    ?spec.watched,
    ?spec.more,
  ];
}

List<FocusableAction> _noticeRow(ReplayActionRowSpec spec, ReplayUnavailableTexts texts) {
  final tail = [if (spec.watched != null) spec.watched!, if (spec.more != null) spec.more!];
  // The menu is where focus lands when nothing on the page can be played.
  final focusIndex = spec.more != null ? tail.length - 1 : 0;
  return [
    FocusableAction(
      debugLabel: 'detail_replay_notice',
      builder: (context, state) {
        final width = MediaQuery.sizeOf(context).width;
        final room = (spec.isTv ? width * 0.6 : width) - 3 * spec.actionSize - _noticeGap - 48;
        return _Notice(
          icon: texts.icon,
          text: texts.notice,
          height: spec.actionSize,
          scale: spec.isTv ? spec.tvScale : 1,
          maxWidth: math.max(160, room),
        );
      },
    ),
    for (var i = 0; i < tail.length; i++)
      _copied(
        tail[i],
        focusNode: i == focusIndex ? spec.primaryFocusNode : null,
        spacingBefore: i == 0 ? _noticeGap : null,
      ),
  ];
}

FocusableAction _copied(FocusableAction a, {FocusNode? focusNode, double? spacingBefore}) => FocusableAction(
  icon: a.icon,
  iconColor: a.iconColor,
  iconFill: a.iconFill,
  iconSize: a.iconSize,
  debugLabel: a.debugLabel,
  focusNode: focusNode ?? a.focusNode,
  autofocus: a.autofocus,
  tooltip: a.tooltip,
  onPressed: a.onPressed,
  child: a.child,
  builder: a.builder,
  spacingBefore: spacingBefore ?? a.spacingBefore,
);

/// The icon and sentence that stand where Play was.
class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final double height;
  final double scale;
  final double maxWidth;

  const _Notice({
    required this.icon,
    required this.text,
    required this.height,
    required this.scale,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ReplayPalette.of(context).ink;
    return Semantics(
      label: text,
      container: true,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, fill: 1, size: 24 * scale, color: ink),
                SizedBox(width: 10 * scale),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 18 * scale, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sign in, drawn like the Play button it replaces.
class _SignInButton extends StatelessWidget {
  final ReplayActionRowSpec spec;
  final bool focused;

  const _SignInButton({required this.spec, required this.focused});

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final scale = spec.isTv ? spec.tvScale : 1.0;
    final ink = focused ? palette.onFocus : palette.ink;
    return Semantics(
      button: true,
      label: t.replay.signIn,
      excludeSemantics: true,
      child: Container(
        height: spec.actionSize,
        padding: EdgeInsets.symmetric(horizontal: 17 * scale),
        decoration: BoxDecoration(
          color: focused ? palette.focus : palette.idle,
          borderRadius: BorderRadius.circular(spec.actionSize / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(Symbols.account_circle_rounded, fill: 1, size: 22 * scale, color: ink),
            SizedBox(width: 7 * scale),
            Text(
              t.replay.signIn,
              style: TextStyle(color: ink, fontSize: 17 * scale, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
