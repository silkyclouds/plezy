import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/replay_channel_logo.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('A channel without a bundled logo shows its initials in the fixed box', (tester) async {
    await tester.pumpWidget(_host(const ReplayChannelLogo.tile(sourceId: 'nologo', name: 'Télé MB')));
    await tester.pump();

    expect(find.text('TM'), findsOneWidget);
    expect(tester.getSize(find.byType(ReplayChannelLogo)), ReplayChannelLogo.tileSize);
  });

  testWidgets('An inline logo falls back to the channel name in the style of its line', (tester) async {
    await tester.pumpWidget(
      _host(
        const ReplayChannelLogo.inline(
          sourceId: 'nologo',
          name: 'Télésambre',
          textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
    await tester.pump();

    final text = tester.widget<Text>(find.text('Télésambre'));
    expect(text.style?.fontSize, 18);
  });

  testWidgets('The plate is 24 high and carries the channel name for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const ReplayChannelLogo.plate(sourceId: 'nologo', name: 'ARTE')));
    await tester.pump();

    expect(tester.getSize(find.byType(Container).first).height, ReplayChannelLogo.plateHeight);
    expect(find.bySemanticsLabel('ARTE'), findsOneWidget);
    semantics.dispose();
  });
}
