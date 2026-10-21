import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/screens/libraries/library_scope.dart';

MediaLibrary _library(String id, MediaBackend backend) => MediaLibrary(id: id, backend: backend, title: id);

void main() {
  group('Catch-up TV tab', () {
    test('is hidden until a catch-up channel is loaded', () {
      final without = NavigationTab.getVisibleTabs(isOffline: false).map((t) => t.id);
      final with_ = NavigationTab.getVisibleTabs(isOffline: false, hasReplay: true).map((t) => t.id);

      expect(without, isNot(contains(NavigationTabId.replay)));
      expect(with_, contains(NavigationTabId.replay));
    });

    test('sits right after Libraries', () {
      final ids = NavigationTab.getVisibleTabs(isOffline: false, hasReplay: true).map((t) => t.id).toList();
      expect(ids[ids.indexOf(NavigationTabId.libraries) + 1], NavigationTabId.replay);
    });

    test('is not offered offline', () {
      final ids = NavigationTab.getVisibleTabs(isOffline: true, hasReplay: true).map((t) => t.id);
      expect(ids, isNot(contains(NavigationTabId.replay)));
    });
  });

  group('LibraryScope', () {
    final libraries = [
      _library('movies', MediaBackend.plex),
      _library('arte', MediaBackend.replay),
      _library('shows', MediaBackend.jellyfin),
      _library('rts', MediaBackend.replay),
    ];

    test('media keeps server libraries and drops channels', () {
      expect(LibraryScope.media.filter(libraries).map((l) => l.id), ['movies', 'shows']);
    });

    test('replay keeps only channels', () {
      expect(LibraryScope.replay.filter(libraries).map((l) => l.id), ['arte', 'rts']);
    });
  });
}
