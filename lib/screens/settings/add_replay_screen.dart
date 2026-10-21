import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import 'connection_persistence.dart';

/// Adds the built-in catch-up TV connection to a profile. It has no server and no account, so the
/// only choice is which broadcasters to show.
class AddReplayScreen extends StatefulWidget {
  final Profile? targetProfile;

  const AddReplayScreen({super.key, this.targetProfile});

  @override
  State<AddReplayScreen> createState() => _AddReplayScreenState();
}

class _AddReplayScreenState extends State<AddReplayScreen> {
  final Set<String> _selected = {...replaySourceIds};
  bool _saving = false;

  Future<void> _add() async {
    final active = context.read<ActiveProfileProvider>();
    final profile = widget.targetProfile ?? active.active;
    if (profile == null) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final connection = ReplayConnection(
      enabledSources: [
        for (final id in replaySourceIds)
          if (_selected.contains(id)) id,
      ],
      createdAt: now,
      lastAuthenticatedAt: now,
    );
    await persistAndBindConnection(
      context: context,
      connection: connection,
      bindToProfile: ProfileConnection(
        profileId: profile.id,
        connectionId: connection.id,
        userIdentifier: ReplayConnection.singletonId,
        tokenAcquiredAt: now,
      ),
    );
    if (!mounted) return;
    if (profile.id == active.activeId) await context.read<ActiveProfileBinder>().rebindIfActive(profile.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(t.addServer.catchUpTvTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(t.addServer.catchUpTvSources, style: Theme.of(context).textTheme.titleMedium),
              for (final id in replaySourceIds)
                CheckboxListTile(
                  value: _selected.contains(id),
                  title: Text(replaySourceName(id)),
                  onChanged: (on) => setState(() => on == true ? _selected.add(id) : _selected.remove(id)),
                ),
              const SizedBox(height: 16),
              FocusableButton(
                autofocus: true,
                onPressed: _saving || _selected.isEmpty ? null : _add,
                child: FilledButton(
                  onPressed: _saving || _selected.isEmpty ? null : _add,
                  child: Text(t.addServer.catchUpTvAdd),
                ),
              ),
              if (_selected.isEmpty) Text(t.addServer.catchUpTvNoSource),
            ]),
          ),
        ),
      ],
    );
  }
}
