import 'package:flutter/material.dart';
import '../theme/clay_theme.dart';

/// The core Claymorphism building block: a soft, puffy, rounded surface
/// using two offset shadows (light top-left, dark bottom-right) instead of
/// a single drop shadow -- this is what makes it look "pressed into clay"
/// rather than just a rounded card floating above the page.
///
/// [pressed] flips to an inset look (shadows swap sides) for toggled/active
/// states, like a button that's currently "pushed in".
class ClayContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final bool pressed;
  final VoidCallback? onTap;

  const ClayContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 24,
    this.color,
    this.pressed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? ClayColors.background;
    final shadows = pressed
        ? [
            BoxShadow(
              color: ClayColors.shadowDark.withOpacity(0.5),
              offset: const Offset(-4, -4),
              blurRadius: 8,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: ClayColors.shadowLight.withOpacity(0.7),
              offset: const Offset(4, 4),
              blurRadius: 8,
              spreadRadius: -2,
            ),
          ]
        : [
            BoxShadow(
              color: ClayColors.shadowLight.withOpacity(0.9),
              offset: const Offset(-6, -6),
              blurRadius: 14,
            ),
            BoxShadow(
              color: ClayColors.shadowDark.withOpacity(0.35),
              offset: const Offset(6, 6),
              blurRadius: 14,
            ),
          ];

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// A small circular clay badge, used for status dots / icon buttons.
class ClayBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final double size;

  const ClayBadge({
    super.key,
    required this.icon,
    this.iconColor = ClayColors.primary,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return ClayContainer(
      borderRadius: size / 2,
      padding: EdgeInsets.all(size * 0.22),
      child: Icon(icon, color: iconColor, size: size * 0.5),
    );
  }
}
