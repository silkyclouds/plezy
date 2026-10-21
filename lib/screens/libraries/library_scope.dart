import '../../media/media_library.dart';

/// Which libraries a [LibrariesScreen] shows: the user's media servers, or the catch-up TV channels.
enum LibraryScope {
  media,
  replay;

  bool includes(MediaLibrary library) => library.backend.isReplay == (this == LibraryScope.replay);

  List<MediaLibrary> filter(Iterable<MediaLibrary> libraries) => [
    for (final library in libraries)
      if (includes(library)) library,
  ];
}
