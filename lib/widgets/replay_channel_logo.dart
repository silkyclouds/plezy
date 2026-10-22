import 'package:flutter/material.dart';

/// A broadcaster's logo in one of the three shapes the catch-up screens use.
///
/// Logos are bundled as `assets/replay/logos/<source id>.png`, drawn light on a transparent background and tinted to
/// the color of the text beside them. When a logo is missing the name stands in for it: as plain text next to other
/// text ([ReplayChannelLogo.inline] and [ReplayChannelLogo.plate]), as a tile of initials in a fixed box
/// ([ReplayChannelLogo.tile]).
class ReplayChannelLogo extends StatelessWidget {
  /// Logo height inside a line of text, and the widest it may grow.
  static const inlineHeight = 16.0;
  static const inlineMaxWidth = 56.0;

  /// Fixed box that keeps names aligned in a column.
  static const tileSize = Size(56, 24);

  /// Height of the plate that carries the logo over artwork.
  static const plateHeight = 24.0;

  final String sourceId;
  final String name;
  final _Shape _shape;
  final double height;
  final double maxWidth;
  final Color? color;
  final TextStyle? textStyle;

  /// The logo replacing the channel name in a line of text. [color] defaults to the text color of the line.
  const ReplayChannelLogo.inline({
    super.key,
    required this.sourceId,
    required this.name,
    this.height = inlineHeight,
    this.maxWidth = inlineMaxWidth,
    this.color,
    this.textStyle,
  }) : _shape = _Shape.inline;

  /// The logo in the fixed 56 x 24 box, centered, with a tile of initials as the fallback.
  const ReplayChannelLogo.tile({super.key, required this.sourceId, required this.name, this.color})
    : _shape = _Shape.tile,
      height = inlineHeight,
      maxWidth = inlineMaxWidth,
      textStyle = null;

  /// The logo on a dark plate that stays readable over any artwork, for the corner of a card.
  const ReplayChannelLogo.plate({super.key, required this.sourceId, required this.name})
    : _shape = _Shape.plate,
      height = inlineHeight,
      maxWidth = inlineMaxWidth,
      color = null,
      textStyle = null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? (_shape == _Shape.plate ? scheme.onSurface : DefaultTextStyle.of(context).style.color);
    final logo = _Logo(
      sourceId: sourceId,
      height: height,
      maxWidth: maxWidth,
      tint: tint,
      alignment: _shape == _Shape.inline ? Alignment.centerLeft : Alignment.center,
      fallback: switch (_shape) {
        _Shape.inline => (_) => Text(name, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        _Shape.tile => (_) => _Initials(name: name),
        _Shape.plate => (c) => Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tint, fontSize: 13, fontWeight: FontWeight.w600, height: 1),
        ),
      },
    );
    final shaped = switch (_shape) {
      _Shape.inline => logo,
      _Shape.tile => SizedBox.fromSize(size: tileSize, child: Center(child: logo)),
      _Shape.plate => Container(
        height: plateHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(4),
        ),
        child: logo,
      ),
    };
    return Semantics(label: name, child: ExcludeSemantics(child: shaped));
  }
}

enum _Shape { inline, tile, plate }

class _Logo extends StatelessWidget {
  final String sourceId;
  final double height;
  final double maxWidth;
  final Color? tint;
  final Alignment alignment;
  final WidgetBuilder fallback;

  const _Logo({
    required this.sourceId,
    required this.height,
    required this.maxWidth,
    required this.tint,
    required this.alignment,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/replay/logos/$sourceId.png',
      height: height,
      fit: BoxFit.contain,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => fallback(context),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height, maxWidth: maxWidth),
      child: tint == null ? image : ColorFiltered(colorFilter: ColorFilter.mode(tint!, BlendMode.srcIn), child: image),
    );
  }
}

/// Two or three letters in a small tile, for a channel whose logo is not bundled.
class _Initials extends StatelessWidget {
  final String name;

  const _Initials({required this.name});

  String get _letters {
    final words = name.split(RegExp(r'[\s.+-]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final text = words.length == 1 ? words.first : words.take(2).map((w) => w[0]).join();
    return text.length > 3 ? text.substring(0, 3) : text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
      child: Text(
        _letters,
        maxLines: 1,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}
