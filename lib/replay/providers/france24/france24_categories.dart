import '../../model/replay_title.dart';
import 'france24_language.dart';

/// Browse id of the general feed of recent videos, newest first.
const france24VideosBrowseId = 'videos';

/// Browse id of the page that lists every programme.
const france24ProgrammesCategory = 'emissions';

/// France 24 has no genre filter; its two sections are the programmes and the general video feed.
List<ReplayCategory> france24Categories(France24Language language) => [
  ReplayCategory(id: france24ProgrammesCategory, title: language.programmesCategoryTitle),
  ReplayCategory(id: france24VideosBrowseId, title: language.videosCategoryTitle),
];
