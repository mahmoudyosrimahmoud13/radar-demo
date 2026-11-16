import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              offset: Offset(-4, -4),
              blurRadius: 8,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: ClayColors.shadowLight.withOpacity(0.7),
              offset: Offset(4, 4),
              blurRadius: 8,
              spreadRadius: -2,
            ),
          ]
        : [
            BoxShadow(
              color: ClayColors.shadowLight.withOpacity(0.9),
              offset: Offset(-6, -6),
              blurRadius: 14,
            ),
            BoxShadow(
              color: ClayColors.shadowDark.withOpacity(0.35),
              offset: Offset(6, 6),
              blurRadius: 14,
            ),
          ];

    final content = AnimatedContainer(
      duration: Duration(milliseconds: 150),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return _PressScale(onTap: onTap!, child: content);
  }
}

/// Gives every tappable clay surface a soft "squish" when pressed, plus a
/// light haptic tick, so taps feel physical.
class _PressScale extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PressScale({required this.onTap, required this.child});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1.0,
        duration: Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A small circular clay badge, used for status dots / icon buttons.
class ClayBadge extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final double size;

  const ClayBadge({
    super.key,
    required this.icon,
    this.iconColor,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return ClayContainer(
      borderRadius: size / 2,
      padding: EdgeInsets.all(size * 0.22),
      child: Icon(icon, color: iconColor ?? ClayColors.primary, size: size * 0.5),
    );
  }
}
