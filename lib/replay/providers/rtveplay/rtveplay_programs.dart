import '../../model/replay_title.dart';
import 'rtveplay_mapper.dart';

/// Whether a programme belongs in a browse list. The programme index mixes in radio networks and programmes that
/// the site's own A-Z leaves out; only the A-Z entries from television have something to watch.
bool rtveIsListable(Map<String, dynamic> program) {
  if (program['inAZList'] != true) return false;
  final channelUid = (program['channel'] as Map?)?['uid'] as String? ?? '';
  return !channelUid.startsWith('CRN_') && !channelUid.startsWith('CHN_');
}

/// Shows for the listable programmes of a page, in the order given.
List<ReplayTitle> rtveShows(Iterable<Map<String, dynamic>> programs) => [
  for (final program in programs)
    if (rtveIsListable(program)) ?rtveShowFromProgram(program),
];

/// Programmes grouped by their `programType` ("Concursos", "Serie Documental"), largest group first.
List<MapEntry<String, List<Map<String, dynamic>>>> rtveGroupByType(Iterable<Map<String, dynamic>> programs) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final program in programs) {
    final type = (program['programType'] as String?)?.trim();
    if (type == null || type.isEmpty || !rtveIsListable(program)) continue;
    groups.putIfAbsent(type, () => []).add(program);
  }
  final entries = groups.entries.toList();
  entries.sort((a, b) => b.value.length.compareTo(a.value.length));
  return entries;
}
