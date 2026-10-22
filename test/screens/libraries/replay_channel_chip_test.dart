import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/screens/libraries/libraries_screen.dart';
import 'package:plezy/screens/libraries/replay_channel_chip.dart';

MediaLibrary _channel(String id, String title) =>
    MediaLibrary(id: id, backend: MediaBackend.replay, title: title, kind: MediaKind.show, serverId: 'replay');

void main() {
  final arte = _channel('arte', 'ARTE');
  final rts = _channel('rtsplay', 'RTS Play');

  testWidgets('the chip names the channel being browsed', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplayChannelChip(
            channels: [arte, rts],
            selected: arte,
            focusNode: focus,
            onSelected: (_) {},
            onNavigateLeft: () {},
            onNavigateRight: () {},
            onNavigateDown: () {},
          ),
        ),
      ),
    );
    expect(find.text('ARTE'), findsOneWidget);
  });

  test('a broadcaster has recommended and browse tabs only', () {
    expect(visibleLibraryTabs(arte), [LibraryTabType.recommended, LibraryTabType.browse]);
  });
}
