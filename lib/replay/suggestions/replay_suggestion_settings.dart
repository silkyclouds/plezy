import '../provider/replay_provider.dart';

/// What the viewer wants on the home screen from catch-up TV.
///
/// By default the home screen offers rows for the channels in languages the viewer follows, so a channel they
/// could not understand never shows up. Every default can be overridden per channel, and a channel's rows can be
/// narrowed or muted one by one.
class ReplaySuggestionSettings {
  static const defaultRowsPerChannel = 2;
  static const maxRowsPerChannel = 4;

  /// Master switch.
  final bool enabled;

  /// ISO 639-1 codes of the languages the viewer follows. Empty means "work it out": the app language plus the
  /// languages of the channels the viewer already watches.
  final Set<String> languages;

  /// The viewer's own decision for a channel, when they made one. It beats the language rule in both directions.
  final Map<String, bool> channels;

  /// For a channel the viewer narrowed down, the only rows to offer (row ids).
  final Map<String, Set<String>> chosenRows;

  /// Rows the viewer asked not to see again, as `channel:rowId`.
  final Set<String> mutedRows;

  final int rowsPerChannel;

  const ReplaySuggestionSettings({
    this.enabled = true,
    this.languages = const {},
    this.channels = const {},
    this.chosenRows = const {},
    this.mutedRows = const {},
    this.rowsPerChannel = defaultRowsPerChannel,
  });

  /// Whether [source] gets rows on the home screen; [automaticLanguages] applies when the viewer set none.
  bool offers(ReplaySource source, Set<String> automaticLanguages) {
    if (!enabled) return false;
    final chosen = channels[source.id];
    if (chosen != null) return chosen;
    final followed = languages.isEmpty ? automaticLanguages : languages;
    return followed.contains(source.language);
  }

  /// Whether the row [rowId] of [sourceId] may be offered.
  bool allowsRow(String sourceId, String rowId) {
    if (mutedRows.contains('$sourceId:$rowId')) return false;
    final only = chosenRows[sourceId];
    return only == null || only.contains(rowId);
  }

  ReplaySuggestionSettings copyWith({
    bool? enabled,
    Set<String>? languages,
    Map<String, bool>? channels,
    Map<String, Set<String>>? chosenRows,
    Set<String>? mutedRows,
    int? rowsPerChannel,
  }) => ReplaySuggestionSettings(
    enabled: enabled ?? this.enabled,
    languages: languages ?? this.languages,
    channels: channels ?? this.channels,
    chosenRows: chosenRows ?? this.chosenRows,
    mutedRows: mutedRows ?? this.mutedRows,
    rowsPerChannel: (rowsPerChannel ?? this.rowsPerChannel).clamp(1, maxRowsPerChannel),
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'languages': languages.toList()..sort(),
    'channels': channels,
    'chosenRows': {for (final e in chosenRows.entries) e.key: e.value.toList()..sort()},
    'mutedRows': mutedRows.toList()..sort(),
    'rowsPerChannel': rowsPerChannel,
  };

  /// Reads a stored record; anything missing or malformed falls back to its default.
  factory ReplaySuggestionSettings.fromJson(Map<String, dynamic> json) {
    final channels = json['channels'];
    final chosen = json['chosenRows'];
    return ReplaySuggestionSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      languages: _strings(json['languages']),
      channels: channels is Map
          ? {
              for (final e in channels.entries)
                if (e.key is String && e.value is bool) e.key as String: e.value as bool,
            }
          : const {},
      chosenRows: chosen is Map
          ? {
              for (final e in chosen.entries)
                if (e.key is String) e.key as String: _strings(e.value),
            }
          : const {},
      mutedRows: _strings(json['mutedRows']),
      rowsPerChannel: json['rowsPerChannel'] is int
          ? (json['rowsPerChannel'] as int).clamp(1, maxRowsPerChannel)
          : defaultRowsPerChannel,
    );
  }

  static Set<String> _strings(Object? value) => value is List
      ? {
          for (final v in value)
            if (v is String) v,
        }
      : const {};
}
