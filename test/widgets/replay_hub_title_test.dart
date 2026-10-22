import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/widgets/replay/replay_hub_title.dart';

MediaHub _hub(String identifier) => MediaHub(
  id: 'arte:docs',
  identifier: identifier,
  title: 'Documentaires',
  type: 'mixed',
  items: const [],
  libraryId: 'arte',
);

void main() {
  test('Only rows built as suggestions get the logo title', () {
    expect(ReplayHubTitle.appliesTo(_hub('replay.suggestion.arte.docs')), isTrue);
    expect(ReplayHubTitle.appliesTo(_hub('replay.arte.docs')), isFalse);
    expect(ReplayHubTitle.appliesTo(_hub('hub.movie.recentlyadded')), isFalse);
  });

  testWidgets('The title reads as one phrase naming the row and the channel', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReplayHubTitle(hub: _hub('replay.suggestion.arte.docs'))),
      ),
    );
    await tester.pump();

    expect(find.text('Documentaires'), findsOneWidget);
    expect(find.bySemanticsLabel('Documentaires on ARTE'), findsOneWidget);
    semantics.dispose();
  });
}
