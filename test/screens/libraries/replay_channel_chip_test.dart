import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/screens/libraries/libraries_screen.dart';
import 'package:plezy/screens/libraries/replay_channel_chip.dart';
import 'package:plezy/screens/libraries/replay_channel_menu.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/replay_channel_logo.dart';

MediaLibrary _channel(String id, String title) =>
    MediaLibrary(id: id, backend: MediaBackend.replay, title: title, kind: MediaKind.show, serverId: 'replay');

/// Owns the chip's focus node so it is disposed with the tree, after the chip lets go of it.
class _ChipHost extends StatefulWidget {
  final List<MediaLibrary> channels;
  final MediaLibrary selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<FocusNode> onNode;

  const _ChipHost({required this.channels, required this.selected, required this.onSelected, required this.onNode});

  @override
  State<_ChipHost> createState() => _ChipHostState();
}

class _ChipHostState extends State<_ChipHost> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.onNode(_node);
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReplayChannelChip(
      channels: widget.channels,
      selected: widget.selected,
      focusNode: _node,
      onSelected: widget.onSelected,
      onNavigateLeft: () {},
      onNavigateRight: () {},
      onNavigateDown: () {},
    );
  }
}

void main() {
  final arte = _channel('arte', 'ARTE');
  final rts = _channel('rtsplay', 'RTS Play');
  final noLogo = _channel('nologo', 'Nologo TV');

  late FocusNode focus;
  String? picked;

  setUp(() => picked = null);

  Future<void> pumpChip(WidgetTester tester, MediaLibrary selected) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: _ChipHost(
              channels: [arte, rts, noLogo],
              selected: selected,
              onSelected: (key) => picked = key,
              onNode: (node) => focus = node,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the chip shows the logo of the channel being browsed', (tester) async {
    await pumpChip(tester, arte);

    final logo = tester.widget<ReplayChannelLogo>(find.byType(ReplayChannelLogo));
    expect(logo.sourceId, 'arte');
    expect(find.bySemanticsLabel('ARTE'), findsOneWidget);
    expect(find.text('ARTE'), findsNothing);
  });

  testWidgets('the chip shows the name when the channel has no logo', (tester) async {
    await pumpChip(tester, noLogo);

    expect(find.text('Nologo TV'), findsOneWidget);
  });

  testWidgets('the chip is 44 high', (tester) async {
    await pumpChip(tester, arte);

    expect(tester.getSize(find.byType(ReplayChannelChip)).height, 44);
  });

  testWidgets('select opens a 300 wide list focused on the current channel', (tester) async {
    await pumpChip(tester, rts);
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ReplayChannelMenuList)).width, 300);
    expect(find.text('ARTE'), findsOneWidget);
    expect(find.text('RTS Play'), findsOneWidget);
    expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
    final focusedRow = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.descendant(of: find.byElementPredicate((e) => e == focusedRow), matching: find.text('RTS Play')),
      findsOneWidget,
    );
  });

  testWidgets('down then select picks the next channel and returns focus to the chip', (tester) async {
    await pumpChip(tester, arte);
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, rts.globalKey);
    expect(find.byType(ReplayChannelMenuList), findsNothing);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('back closes the list without changing the channel', (tester) async {
    await pumpChip(tester, arte);
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(picked, isNull);
    expect(find.byType(ReplayChannelMenuList), findsNothing);
    expect(focus.hasFocus, isTrue);
  });

  test('a broadcaster has recommended and browse tabs only', () {
    expect(visibleLibraryTabs(arte), [LibraryTabType.recommended, LibraryTabType.browse]);
  });
}
