import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../replay/suggestions/replay_suggestion_events.dart';
import '../../../replay/suggestions/replay_suggestion_settings.dart';
import '../../../replay/suggestions/replay_suggestion_store.dart';
import '../../../utils/app_logger.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_menu.dart';
import '../../../widgets/focused_scroll_scaffold.dart';
import 'replay_language_chips.dart';
import 'replay_menu.dart';
import 'replay_palette.dart';
import 'replay_row.dart';
import 'replay_rows_dialog.dart';
import 'replay_suggestion_channels.dart';
import 'replay_suggestion_rows.dart';
import 'replay_suggestion_view.dart';

typedef ReplayRowChoices = Future<List<({String id, String title})>> Function(String sourceId);

/// What the home screen offers from catch-up TV: the master switch, the languages followed, how many rows per
/// channel, and for each enabled channel whether it is on and which of its rows. Every change is saved at once.
class ReplaySuggestionsScreen extends StatefulWidget {
  final ReplaySuggestionStore store;
  final Future<Set<String>> Function() automaticLanguages;
  final ReplayRowChoices rowChoices;

  /// The channels enabled in the catch-up settings.
  final List<ReplaySourceInfo> channels;
  final String locale;

  /// A channel to put the focus on when the screen opens.
  final String? focusChannel;

  const ReplaySuggestionsScreen({
    super.key,
    required this.store,
    required this.automaticLanguages,
    required this.rowChoices,
    required this.channels,
    required this.locale,
    this.focusChannel,
  });

  @override
  State<ReplaySuggestionsScreen> createState() => _ReplaySuggestionsScreenState();
}

class _ReplaySuggestionsScreenState extends State<ReplaySuggestionsScreen> {
  ReplaySuggestionSettings? _settings;
  Set<String> _automatic = const {};
  final Map<String, Map<String, String>> _titles = {};
  final Map<String, FocusNode> _nodes = {};
  bool _editingRows = false;

  late final List<ReplaySourceInfo> _channels = [...widget.channels]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await widget.store.load();
    final automatic = await widget.automaticLanguages();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _automatic = automatic;
    });
    final focus = widget.focusChannel;
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _nodes[focus]?.requestFocus());
    }
    for (final info in _channels) {
      if (settings.chosenRows.containsKey(info.id) || settings.mutedRows.any((m) => m.startsWith('${info.id}:'))) {
        unawaited(_fetchTitles(info.id));
      }
    }
  }

  FocusNode _nodeFor(String sourceId) => _nodes.putIfAbsent(sourceId, () => FocusNode(debugLabel: 'suggest-$sourceId'));

  Future<List<({String id, String title})>> _fetchTitles(String sourceId) async {
    try {
      final choices = await widget.rowChoices(sourceId);
      if (mounted) setState(() => _titles[sourceId] = {for (final c in choices) c.id: c.title});
      return choices;
    } on Exception catch (error) {
      appLogger.w('Could not list the rows of $sourceId', error: error);
      return const [];
    }
  }

  void _save(ReplaySuggestionSettings next) {
    setState(() => _settings = next);
    unawaited(widget.store.save(next).whenComplete(notifyReplaySuggestionsChanged));
  }

  void _toggleLanguage(String code) {
    final settings = _settings!;
    final next = toggledLanguages(settings, _automatic, code);
    if (next != null) _save(settings.copyWith(languages: next));
  }

  void _toggleChannel(ReplaySourceInfo info, bool on) =>
      _save(_settings!.copyWith(channels: {..._settings!.channels, info.id: on}));

  void _resetChannel(ReplaySourceInfo info) {
    _save(_settings!.copyWith(channels: {..._settings!.channels}..remove(info.id)));
    WidgetsBinding.instance.addPostFrameCallback((_) => _nodeFor(info.id).requestFocus());
  }

  Future<void> _pickRowsPerChannel(BuildContext rowContext) async {
    final settings = _settings!;
    final count = await showReplayMenu<int>(
      rowContext,
      anchor: replayAnchorRect(rowContext),
      alignment: AppMenuAnchorAlignment.end,
      width: 200,
      entries: [
        for (var n = 1; n <= ReplaySuggestionSettings.maxRowsPerChannel; n++)
          ReplayMenuEntry(value: n, label: '$n', selected: n == settings.rowsPerChannel),
      ],
    );
    if (count != null) _save(settings.copyWith(rowsPerChannel: count));
  }

  Future<void> _editRows(ReplaySourceInfo info) async {
    if (_editingRows) return;
    _editingRows = true;
    try {
      final choices = await _fetchTitles(info.id);
      if (!mounted) return;
      final settings = _settings!;
      final ids = [for (final choice in choices) choice.id];
      final selection = await showReplayRowsDialog(
        context,
        info: info,
        choices: choices,
        initial: currentRowSelection(settings, info.id, ids),
        rowsPerChannel: settings.rowsPerChannel,
        locale: widget.locale,
      );
      if (selection != null && mounted) _save(withRowSelection(_settings!, info.id, ids, selection));
    } finally {
      _editingRows = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return FocusedScrollScaffold(
      title: Text(t.replay.suggestions.title),
      slivers: [
        SliverToBoxAdapter(
          child: settings == null
              ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              : _content(settings),
        ),
      ],
    );
  }

  Widget _content(ReplaySuggestionSettings settings) {
    final palette = ReplayPalette.of(context);
    final master = settings.enabled;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: palette.group, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReplayRow(
                  lead: const AppIcon(Symbols.home_rounded, size: 26),
                  title: t.replay.suggestions.title,
                  details: [Text(t.replay.suggestions.masterHint)],
                  trailing: ReplayRow.switchOf(master),
                  onSelect: () => _save(settings.copyWith(enabled: !master)),
                ),
                ReplayLanguageChips(
                  languages: languagesOfChannels(_channels, widget.locale),
                  followed: followedLanguages(settings, _automatic),
                  manual: settings.languages.isNotEmpty,
                  enabled: master,
                  locale: widget.locale,
                  onToggle: _toggleLanguage,
                  onResetToAutomatic: () => _save(settings.copyWith(languages: const {})),
                ),
                Builder(
                  builder: (rowContext) => ReplayRow(
                    enabled: master,
                    lead: const AppIcon(Symbols.view_agenda_rounded, size: 26),
                    title: t.replay.suggestions.rowsPerChannel,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${settings.rowsPerChannel}', style: const TextStyle(fontSize: 17)),
                        const SizedBox(width: 6),
                        const AppIcon(Symbols.chevron_right_rounded, size: 28),
                      ],
                    ),
                    onSelect: () => unawaited(_pickRowsPerChannel(rowContext)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.replay.suggestions.channels,
                  style: TextStyle(color: palette.muted, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(t.replay.suggestions.channelsHint, style: TextStyle(color: palette.muted, fontSize: 15)),
              ],
            ),
          ),
          ReplaySuggestionChannels(
            channels: _channels,
            settings: settings,
            automatic: _automatic,
            locale: widget.locale,
            titles: _titles,
            focusNodeFor: _nodeFor,
            onToggle: _toggleChannel,
            onEditRows: (info) => unawaited(_editRows(info)),
            onResetChoice: _resetChannel,
          ),
        ],
      ),
    );
  }
}
