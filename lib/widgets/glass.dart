import 'dart:ui';

import 'package:flutter/material.dart';

/// The pair of colours a screen washes its background with.
///
/// Every screen carries its own tint and the glass on top of it stays the same.
/// The tints are interpolated against the nav bar's fractional position, so the
/// background moves *with* the thumb instead of cutting over after it lands.
class ScreenTint {
  const ScreenTint(this.a, this.b);

  final Color a;
  final Color b;

  static ScreenTint lerp(ScreenTint x, ScreenTint y, double t) =>
      ScreenTint(Color.lerp(x.a, y.a, t)!, Color.lerp(x.b, y.b, t)!);
}

/// Surface tokens for the glass, in both brightnesses.
extension GlassTokens on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get glassFill => isDark
      ? Colors.white.withValues(alpha: 0.09)
      : Colors.white.withValues(alpha: 0.62);

  Color get glassStroke => isDark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.9);

  /// For the sunken readouts — a command line, a rate — that should read as a
  /// hole in the card rather than another card.
  Color get glassWell => isDark
      ? Colors.black.withValues(alpha: 0.3)
      : Colors.black.withValues(alpha: 0.05);

  Color get glassMuted => (isDark ? Colors.white : Colors.black)
      .withValues(alpha: isDark ? 0.58 : 0.55);

  List<BoxShadow> get glassShadow => [
        BoxShadow(
          blurRadius: 30,
          offset: const Offset(0, 10),
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
        ),
      ];
}

/// Flat base colour plus three soft washes of the screen's tint.
///
/// Painted as radial gradients rather than as blurred circles: a blur of that
/// radius is the most expensive thing that could sit under a live camera
/// preview, and a gradient is already soft at its edge.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.tint});

  final ScreenTint tint;

  static const baseDark = Color(0xFF07090F);
  static const baseLight = Color(0xFFF1F3F8);

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return TweenAnimationBuilder<Color?>(
      // The theme itself cross-fades when the system flips; the background has
      // to be told to.
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      tween: ColorTween(end: dark ? baseDark : baseLight),
      builder: (context, base, _) => CustomPaint(
        isComplex: true,
        painter: _AmbientPainter(base: base!, tint: tint, dark: dark),
        size: Size.infinite,
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({
    required this.base,
    required this.tint,
    required this.dark,
  });

  final Color base;
  final ScreenTint tint;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    void orb(Offset centre, double radius, Color colour, double opacity) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colour.withValues(alpha: opacity),
              colour.withValues(alpha: opacity * 0.3),
              colour.withValues(alpha: 0),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    final w = size.width;
    final h = size.height;
    orb(Offset(w * 0.16, h * 0.05), w * 0.66, tint.a, dark ? 0.55 : 0.4);
    orb(Offset(w * 1.02, h * 0.74), w * 0.6, tint.b, dark ? 0.45 : 0.32);
    orb(Offset(-w * 0.06, h * 0.46), w * 0.48, tint.b, dark ? 0.22 : 0.16);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.base != base || old.tint.a != tint.a || old.tint.b != tint.b;
}

/// One pane of glass. [blur] costs a `BackdropFilter`, so it is off unless the
/// card actually has something worth blurring behind it — a camera frame, the
/// content scrolling under the nav bar. Over the ambient wash a translucent
/// fill is indistinguishable and free.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
    this.blur = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    Widget pane = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.glassFill,
        borderRadius: shape,
        border: Border.all(color: context.glassStroke),
      ),
      child: child,
    );

    if (blur) {
      pane = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: pane,
        ),
      );
    }

    if (onTap != null) {
      pane = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pane,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: context.glassShadow),
      child: pane,
    );
  }
}

/// A sunken monospace readout — the command on the wire, a rate, an address.
class GlassWell extends StatelessWidget {
  const GlassWell({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.glassWell,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (context.isDark ? Colors.white : Colors.black)
              .withValues(alpha: 0.08),
        ),
      ),
      child: child,
    );
  }
}

/// The small uppercase line that labels a group.
class GlassLabel extends StatelessWidget {
  const GlassLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: context.glassMuted,
          ),
        ),
      );
}

/// Numbers that must not shuffle sideways as they change. Every angle, rate and
/// address in the app is drawn with this.
TextStyle monoStyle({
  required double size,
  Color? colour,
  FontWeight weight = FontWeight.w500,
}) =>
    TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: weight,
      color: colour,
      letterSpacing: -0.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
