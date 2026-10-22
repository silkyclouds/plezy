import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../replay/suggestions/replay_suggestion_settings.dart';
import '../../../replay/suggestions/replay_suggestion_store.dart';
import '../../../widgets/app_icon.dart';
import 'replay_palette.dart';
import 'replay_row.dart';
import 'replay_suggestion_view.dart';

/// The line of the catch-up settings that opens the home suggestions screen, with a summary of how they are set.
class ReplaySuggestionsEntry extends StatefulWidget {
  final ReplaySuggestionStore store;
  final Future<Set<String>> Function() automaticLanguages;
  final List<ReplaySourceInfo> enabledChannels;
  final String locale;

  /// Opens the suggestions screen; the summary is read again when it completes.
  final Future<void> Function() onOpen;

  const ReplaySuggestionsEntry({
    super.key,
    required this.store,
    required this.automaticLanguages,
    required this.enabledChannels,
    required this.locale,
    required this.onOpen,
  });

  @override
  State<ReplaySuggestionsEntry> createState() => _ReplaySuggestionsEntryState();
}

class _ReplaySuggestionsEntryState extends State<ReplaySuggestionsEntry> {
  ReplaySuggestionSettings? _settings;
  Set<String> _automatic = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    final automatic = await widget.automaticLanguages();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _automatic = automatic;
    });
  }

  Future<void> _open() async {
    await widget.onOpen();
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final summary = settings == null
        ? ''
        : suggestionsEntrySummary(
            settings: settings,
            automatic: _automatic,
            enabledChannels: widget.enabledChannels,
            locale: widget.locale,
          );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: ReplayPalette.of(context).group, borderRadius: BorderRadius.circular(12)),
      child: ReplayRow(
        lead: const AppIcon(Symbols.home_rounded, size: 26),
        title: t.replay.suggestions.title,
        details: [Text(summary)],
        trailing: const AppIcon(Symbols.chevron_right_rounded, size: 28),
        onSelect: () => unawaited(_open()),
      ),
    );
  }
}
