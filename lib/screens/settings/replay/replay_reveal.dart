import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Scrolls so that the widget behind [context] sits just under the pinned title bar, once the next frame has laid it
/// out. Used after a drawer opens, so the opened country starts where the eye already is.
void revealBelowTitleBar(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final target = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (target is! RenderBox || !target.attached || scrollable == null) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) return;
    final inset = MediaQuery.paddingOf(context).top + kToolbarHeight + 24;
    final position = scrollable.position;
    final offset = viewport.getOffsetToReveal(target, 0).offset - inset;
    position.animateTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  });
}
