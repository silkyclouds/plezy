import '../../../i18n/strings.g.dart';
import '../../../replay/suggestions/replay_suggestion_settings.dart';

/// Longest "Rangées : ..." line shown before it falls back to a count.
const _summaryLimit = 40;

/// What the viewer sees in the rows dialog of one channel.
class ReplayRowSelection {
  /// Rows the channel adds later are offered too; the unticked ones stay hidden.
  final bool includeNew;
  final Set<String> ticked;

  const ReplayRowSelection({required this.includeNew, required this.ticked});

  ReplayRowSelection copyWith({bool? includeNew, Set<String>? ticked}) =>
      ReplayRowSelection(includeNew: includeNew ?? this.includeNew, ticked: ticked ?? this.ticked);
}

String _mutedKey(String sourceId, String rowId) => '$sourceId:$rowId';

Set<String> _mutedOf(ReplaySuggestionSettings settings, String sourceId) {
  final prefix = '$sourceId:';
  return {
    for (final key in settings.mutedRows)
      if (key.startsWith(prefix)) key.substring(prefix.length),
  };
}

/// The state the dialog opens with, for the rows [rowIds] the channel publishes now.
ReplayRowSelection currentRowSelection(ReplaySuggestionSettings settings, String sourceId, List<String> rowIds) {
  final only = settings.chosenRows[sourceId];
  if (only != null) {
    return ReplayRowSelection(
      includeNew: false,
      ticked: {
        for (final id in rowIds)
          if (only.contains(id)) id,
      },
    );
  }
  final muted = _mutedOf(settings, sourceId);
  return ReplayRowSelection(
    includeNew: true,
    ticked: {
      for (final id in rowIds)
        if (!muted.contains(id)) id,
    },
  );
}

/// [settings] with the channel's rows set to [selection]. Rows the channel no longer publishes keep their old
/// state, so they come back as they were if the channel brings them back.
ReplaySuggestionSettings withRowSelection(
  ReplaySuggestionSettings settings,
  String sourceId,
  List<String> rowIds,
  ReplayRowSelection selection,
) {
  final known = rowIds.toSet();
  final muted = {
    for (final key in settings.mutedRows)
      if (!known.any((id) => key == _mutedKey(sourceId, id))) key,
  };
  final chosen = {...settings.chosenRows}..remove(sourceId);
  if (selection.includeNew) {
    muted.addAll([
      for (final id in rowIds)
        if (!selection.ticked.contains(id)) _mutedKey(sourceId, id),
    ]);
  } else {
    final unseen = {...?settings.chosenRows[sourceId]}..removeAll(known);
    chosen[sourceId] = {...selection.ticked, ...unseen};
  }
  return settings.copyWith(chosenRows: chosen, mutedRows: muted);
}

/// The "Rangées : ..." line under a channel. [titles] maps row ids to names, and is null while they are not known,
/// in which case counts stand in for names.
String rowsSummaryLine(ReplaySuggestionSettings settings, String sourceId, Map<String, String>? titles) {
  final only = settings.chosenRows[sourceId];
  final muted = _mutedOf(settings, sourceId);
  final s = t.replay.suggestions;
  if (only == null && muted.isEmpty) return s.rowsLabel(summary: s.rowsAll);
  final ids = only ?? muted;
  final names = titles == null ? null : [for (final id in ids) ?titles[id]];
  final countForm = only != null ? s.rowsChosenCount(count: ids.length) : s.rowsAllButCount(count: ids.length);
  if (names == null || names.length != ids.length) return s.rowsLabel(summary: countForm);
  final full = only != null ? names.join(', ') : s.rowsAllBut(titles: names.join(', '));
  final line = s.rowsLabel(summary: full);
  return line.length > _summaryLimit ? s.rowsLabel(summary: countForm) : line;
}
