import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../replay/provider/replay_source_groups.dart';
import '../../../replay/provider/replay_source_info.dart';
import 'replay_channel_filter.dart';
import 'replay_channel_row.dart';
import 'replay_country_drawer.dart';
import 'replay_country_phrases.dart';
import 'replay_palette.dart';

/// The "Chaînes par pays" part of the settings: one drawer per country, only one open at a time, or only the channels
/// found while the viewer searches.
class ReplayChannelList extends StatefulWidget {
  final List<ReplayCountryGroup> groups;
  final Set<String> enabled;
  final String query;
  final String locale;
  final String? viewerCountry;

  /// The country whose drawer is open, when not searching.
  final String? expandedCountry;

  /// Whether the channel has an account and the app can sign in to it.
  final bool Function(ReplaySourceInfo info) hasAccount;
  final bool Function(ReplaySourceInfo info) isSignedIn;
  final ValueChanged<String> onToggleCountry;
  final void Function(Set<String> sourceIds, bool on) onSetEnabled;
  final void Function(ReplaySourceInfo info, BuildContext rowContext) onAccount;

  const ReplayChannelList({
    super.key,
    required this.groups,
    required this.enabled,
    required this.query,
    required this.locale,
    required this.viewerCountry,
    required this.expandedCountry,
    required this.hasAccount,
    required this.isSignedIn,
    required this.onToggleCountry,
    required this.onSetEnabled,
    required this.onAccount,
  });

  @override
  State<ReplayChannelList> createState() => _ReplayChannelListState();
}

class _ReplayChannelListState extends State<ReplayChannelList> {
  bool _initialFocusPending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialFocusPending = false);
  }

  bool get _searching => isReplaySearch(widget.query);

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    final shown = _searching ? filterReplayGroups(widget.groups, widget.query) : widget.groups;
    final firstCountry = widget.groups.isEmpty ? null : widget.groups.first.country;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Text(
            t.replay.setup.byCountry,
            style: TextStyle(color: palette.muted, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(t.replay.setup.noMatch(query: widget.query.trim()), style: const TextStyle(fontSize: 17)),
          ),
        for (final group in shown)
          _drawer(group, full: _fullGroup(group.country), autofocus: group.country == firstCountry),
      ],
    );
  }

  ReplayCountryGroup _fullGroup(String country) => widget.groups.firstWhere((group) => group.country == country);

  Widget _drawer(ReplayCountryGroup group, {required ReplayCountryGroup full, required bool autofocus}) {
    final sources = full.sources;
    return ReplayCountryDrawer(
      key: ValueKey(group.country),
      group: group,
      total: sources.length,
      enabledCount: sources.where((info) => widget.enabled.contains(info.id)).length,
      blockedCount: sources.where((info) => info.restrictsViewerIn(widget.viewerCountry)).length,
      locale: widget.locale,
      viewerCountry: widget.viewerCountry,
      expanded: widget.expandedCountry == group.country,
      pinnedOpen: _searching,
      autofocusHeader: autofocus && _initialFocusPending && !_searching,
      onToggle: () => widget.onToggleCountry(group.country),
      onToggleAll: (on) => widget.onSetEnabled({for (final info in sources) info.id}, on),
      channelBuilder: (info) => _channel(info),
    );
  }

  Widget _channel(ReplaySourceInfo info) {
    final on = widget.enabled.contains(info.id);
    final viewer = widget.viewerCountry;
    return Column(
      key: ValueKey(info.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReplayChannelRow(
          info: info,
          enabled: on,
          locale: widget.locale,
          blockedFrom: viewer != null && info.restrictsViewerIn(viewer)
              ? replayCountryFrom(viewer, widget.locale)
              : null,
          onChanged: (value) => widget.onSetEnabled({info.id}, value),
        ),
        if (on && widget.hasAccount(info))
          ReplayAccountRow(
            info: info,
            connected: widget.isSignedIn(info),
            onPressed: (rowContext) => widget.onAccount(info, rowContext),
          ),
      ],
    );
  }
}
