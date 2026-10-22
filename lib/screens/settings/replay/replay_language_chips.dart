import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../widgets/app_icon.dart';
import 'replay_palette.dart';
import 'replay_pill.dart';
import 'replay_row.dart';

/// The "Langues suivies" block: one chip per language the enabled channels speak, ticked when followed, and a last
/// chip to go back to automatic once the viewer chose by hand.
class ReplayLanguageChips extends StatelessWidget {
  /// Language codes in display order.
  final List<String> languages;
  final Set<String> followed;
  final bool manual;
  final bool enabled;
  final String locale;
  final ValueChanged<String> onToggle;
  final VoidCallback onResetToAutomatic;

  const ReplayLanguageChips({
    super.key,
    required this.languages,
    required this.followed,
    required this.manual,
    required this.enabled,
    required this.locale,
    required this.onToggle,
    required this.onResetToAutomatic,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final ink = enabled ? palette.ink : palette.inactive;
    final detail = enabled ? palette.muted : palette.inactive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(ReplayRow.groupInset + 20, 14, ReplayRow.groupInset + 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ReplayRow.leadWidth,
            child: Center(child: AppIcon(Symbols.translate_rounded, size: 26, color: ink)),
          ),
          const SizedBox(width: ReplayRow.leadGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.replay.suggestions.languagesTitle, style: TextStyle(color: ink, fontSize: 17, height: 1.3)),
                Text(
                  manual ? t.replay.suggestions.languagesManual : t.replay.suggestions.languagesAuto,
                  style: TextStyle(color: detail, fontSize: 15, height: 1.35),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final code in languages)
                      ReplayPill(
                        label: replayLanguageName(code, locale),
                        selected: followed.contains(code),
                        enabled: enabled,
                        lead: followed.contains(code)
                            ? (color) => AppIcon(Symbols.check_rounded, size: 20, color: color)
                            : null,
                        onPressed: () => onToggle(code),
                      ),
                    if (manual)
                      ReplayPill(
                        label: t.replay.suggestions.backToAuto,
                        enabled: enabled,
                        onPressed: onResetToAutomatic,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
