import 'package:flutter/material.dart';

import 'replay_palette.dart';

/// The surface of the catch-up dialogs: a raised, rounded panel of a fixed width, scrolling when the screen is short.
class ReplayDialogFrame extends StatelessWidget {
  final double width;
  final double padding;
  final Widget child;

  const ReplayDialogFrame({super.key, required this.width, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Material(
            color: palette.raised,
            elevation: 12,
            shadowColor: Theme.of(context).colorScheme.shadow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(padding: EdgeInsets.all(padding), child: child),
          ),
        ),
      ),
    );
  }
}
