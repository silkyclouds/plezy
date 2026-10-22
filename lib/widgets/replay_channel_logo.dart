import 'package:flutter/material.dart';

/// A broadcaster's logo at a fixed height, or its initials in a small tile when the logo is not bundled.
///
/// Logos are bundled as `assets/replay/logos/<source id>.png`. They are drawn light for the dark theme, so they sit
/// directly on the surface with no plate behind them.
class ReplayChannelLogo extends StatelessWidget {
  final String sourceId;
  final String name;
  final double height;

  const ReplayChannelLogo({super.key, required this.sourceId, required this.name, this.height = 24});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height, maxWidth: height * 3),
      child: Image.asset(
        'assets/replay/logos/$sourceId.png',
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => _Initials(name: name, height: height),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final double height;

  const _Initials({required this.name, required this.height});

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
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(height * 0.22),
      ),
      child: Text(
        _letters,
        maxLines: 1,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: height * 0.42,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
