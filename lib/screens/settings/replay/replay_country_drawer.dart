import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_regions.dart';
import '../../../replay/provider/replay_source_groups.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/focusable_list_tile.dart';

/// One country of the setup screen: a header that opens and closes, and inside it the channels, split by language when
/// the country has more than one. The caller draws the channels, because they carry the switches and sign-in rows.
class ReplayCountryDrawer extends StatelessWidget {
  final ReplayCountryGroup group;
  final String locale;
  final int enabledCount;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> Function(ReplaySourceInfo source) channelBuilder;

  const ReplayCountryDrawer({
    super.key,
    required this.group,
    required this.locale,
    required this.enabledCount,
    required this.expanded,
    required this.onToggle,
    required this.channelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = group.sources.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            FocusableListTile(
              leading: _CountryBadge(code: group.country),
              title: Text(replayCountryName(group.country, locale)),
              subtitle: Text(t.replay.setup.enabledCount(enabled: enabledCount, total: total)),
              trailing: AppIcon(expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, fill: 1),
              onTap: onToggle,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded ? _channels(context) : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channels(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final splitByLanguage = group.languages.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final language in group.languages) ...[
          if (splitByLanguage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text(
                replayLanguageName(language.language, locale),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
          for (final source in language.sources) ...channelBuilder(source),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}

/// The ISO code of a country in a small rounded tile, or a globe for international channels.
class _CountryBadge extends StatelessWidget {
  final String code;

  const _CountryBadge({required this.code});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(7)),
      child: code == replayInternational
          ? AppIcon(Symbols.public_rounded, fill: 1, size: 18, color: scheme.onSurfaceVariant)
          : Text(
              code,
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12),
            ),
    );
  }
}
