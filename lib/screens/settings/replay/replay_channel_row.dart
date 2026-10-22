import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_provider.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/replay_channel_logo.dart';
import 'replay_palette.dart';
import 'replay_row.dart';

String _supportLabel(ReplayPlaybackSupport support) => switch (support) {
  ReplayPlaybackSupport.clear => t.replay.supportClear,
  ReplayPlaybackSupport.partial => t.replay.supportPartial,
  ReplayPlaybackSupport.browseOnly => t.replay.supportBrowseOnly,
};

/// The line under a channel name: what plays, then the languages when the channel has several.
String replayChannelSubtitle(ReplaySourceInfo info, String locale) {
  final support = _supportLabel(info.support);
  if (info.languages.length < 2) return support;
  return '$support · ${info.languages.map((code) => replayLanguageName(code, locale)).join(', ')}';
}

/// A channel: logo, name, how much of it plays, a warning when the viewer's country is outside its rights, and the
/// switch. Turning a channel off leaves its name in full ink; only the switch changes.
class ReplayChannelRow extends StatelessWidget {
  final ReplaySourceInfo info;
  final bool enabled;
  final String locale;

  /// Not null when the channel does not play from the viewer's country: the country as written after "from".
  final String? blockedFrom;
  final ValueChanged<bool> onChanged;

  const ReplayChannelRow({
    super.key,
    required this.info,
    required this.enabled,
    required this.locale,
    required this.blockedFrom,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    return ReplayRow(
      lead: ReplayChannelLogo.tile(sourceId: info.id, name: info.name),
      title: info.name,
      minHeight: blockedFrom == null ? 75 : 96,
      details: [
        Text(replayChannelSubtitle(info, locale)),
        if (blockedFrom != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                AppIcon(Symbols.public_off_rounded, size: 18, color: palette.ink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    t.replay.setup.notFromHere(country: blockedFrom!),
                    style: TextStyle(color: palette.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
      trailing: ReplayRow.switchOf(enabled),
      onSelect: () => onChanged(!enabled),
    );
  }
}

/// The line under a signed-in-capable channel: signs in, or opens the account menu.
class ReplayAccountRow extends StatelessWidget {
  final ReplaySourceInfo info;
  final bool connected;

  /// Called with the row's context so a menu can be anchored to it.
  final void Function(BuildContext rowContext) onPressed;

  const ReplayAccountRow({super.key, required this.info, required this.connected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    return Builder(
      builder: (rowContext) => ReplayRow(
        lead: const AppIcon(Symbols.account_circle_rounded, size: 26),
        title: connected ? t.replay.setup.account(name: info.name) : t.replay.setup.signInTo(name: info.name),
        minHeight: 56,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connected)
              Text(t.replay.setup.connected, style: TextStyle(color: palette.muted, fontSize: 15)),
            const SizedBox(width: 6),
            const AppIcon(Symbols.chevron_right_rounded, size: 28),
          ],
        ),
        onSelect: () => onPressed(rowContext),
      ),
    );
  }
}
