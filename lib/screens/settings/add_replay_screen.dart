import 'package:flutter/material.dart';

import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/profile.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import 'replay_connection_setup.dart';

/// Adds the built-in catch-up TV connection to a profile. It has no server and no account, so the
/// only choice is which broadcasters to show.
class AddReplayScreen extends StatefulWidget {
  final Profile? targetProfile;

  const AddReplayScreen({super.key, this.targetProfile});

  @override
  State<AddReplayScreen> createState() => _AddReplayScreenState();
}

class _AddReplayScreenState extends State<AddReplayScreen> {
  late final Set<String> _selected = {...replaySourceIds};
  bool _saving = false;

  Future<void> _add() async {
    setState(() => _saving = true);
    final added = await addReplayConnection(context, sources: _selected, targetProfile: widget.targetProfile);
    if (!mounted) return;
    if (added) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
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
              FocusableButton(
                autofocus: true,
                onPressed: _saving || _selected.isEmpty ? null : _add,
                child: FilledButton(
                  onPressed: _saving || _selected.isEmpty ? null : _add,
                  child: Text(t.addServer.catchUpTvAdd),
                ),
              ),
              if (_selected.isEmpty) Text(t.addServer.catchUpTvNoSource),
              const SizedBox(height: 16),
              Text(t.addServer.catchUpTvSources, style: Theme.of(context).textTheme.titleMedium),
              for (final id in replaySourceIds)
                CheckboxListTile(
                  value: _selected.contains(id),
                  title: Text(replaySourceName(id)),
                  onChanged: (on) => setState(() => on == true ? _selected.add(id) : _selected.remove(id)),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}
