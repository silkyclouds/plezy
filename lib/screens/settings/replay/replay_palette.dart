import 'package:flutter/material.dart';

import '../../../theme/mono_tokens.dart';

/// The fills the catch-up settings screens draw with, derived from the active theme so they follow it.
///
/// Focus is always the strongest state: [focus] is lighter than [idle], [selected] and [raised].
@immutable
class ReplayPalette {
  /// Fill of a settings group.
  final Color group;

  /// Fill of menus, dialogs and a focused settings row.
  final Color raised;

  /// Resting fill of a chip, button or text field.
  final Color idle;

  /// A chosen chip that does not have focus.
  final Color selected;

  /// A text field that has focus.
  final Color fieldFocus;

  /// Fill of the focused element and the ink on it.
  final Color focus;
  final Color onFocus;

  /// Text on a resting or selected element, secondary text and text of an inactive element.
  final Color ink;
  final Color muted;
  final Color inactive;

  const ReplayPalette({
    required this.group,
    required this.raised,
    required this.idle,
    required this.selected,
    required this.fieldFocus,
    required this.focus,
    required this.onFocus,
    required this.ink,
    required this.muted,
    required this.inactive,
  });

  factory ReplayPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = tokens(context).surface;
    final idle = Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.06), group);
    return ReplayPalette(
      group: group,
      raised: Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.08), scheme.surface),
      idle: idle,
      selected: Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), idle),
      fieldFocus: Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), group),
      focus: scheme.primary,
      onFocus: scheme.onPrimary,
      ink: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      inactive: scheme.onSurface.withValues(alpha: 0.5),
    );
  }
}
