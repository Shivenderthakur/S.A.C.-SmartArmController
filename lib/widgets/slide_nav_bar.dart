import 'dart:ui';

import 'package:flutter/material.dart';

import 'glass.dart';
import 'slide_selection.dart';

class NavDestination {
  const NavDestination(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The floating glass bar, and the thing you scrub.
///
/// A tap selects, but so does a press and drag: hold anywhere on the bar and
/// slide, and the pill comes to your thumb and follows it, with a click of
/// haptic feedback at each boundary. Because [SlideSelection] keeps the
/// position as a fraction, nothing here snaps — the pill, the icon scales, the
/// label colours and the screens behind all read off the same number, so the
/// whole app moves as one thing under the finger rather than four that fade.
class SlideNavBar extends StatelessWidget {
  const SlideNavBar({
    super.key,
    required this.destinations,
    required this.selection,
    required this.accent,
  });

  static const height = 68.0;
  static const _inset = 6.0;

  final List<NavDestination> destinations;
  final SlideSelection selection;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final shape = BorderRadius.circular(height / 2);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            blurRadius: 40,
            offset: const Offset(0, 16),
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          // The one place a real blur earns its cost: content scrolls under
          // this, and on the tracking screen so does the camera.
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.6),
              borderRadius: shape,
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.9),
              ),
            ),
            child: SlideSelectionDetector(
              selection: selection,
              padding: _inset,
              child: AnimatedBuilder(
                animation: selection,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final each = (constraints.maxWidth - _inset * 2) /
                        destinations.length;

                    return Stack(
                      children: [
                        Positioned(
                          left: _inset + selection.position * each,
                          top: _inset,
                          bottom: _inset,
                          width: each,
                          child: _Pill(
                            accent: accent,
                            // Lightens as it moves, so a scrub looks like the
                            // pill is being carried rather than dragged.
                            lift: selection.dragging ? 1 : selection.travel,
                          ),
                        ),
                        Row(
                          children: [
                            SizedBox(width: _inset),
                            for (var i = 0; i < destinations.length; i++)
                              SizedBox(
                                width: each,
                                child: _Item(
                                  destination: destinations[i],
                                  weight: selection.weightFor(i),
                                  selected: onSurface,
                                  idle: context.glassMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.accent, required this.lift});

  final Color accent;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: (dark ? 0.3 : 0.24) + lift * 0.08,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: accent.withValues(alpha: dark ? 0.4 : 0.3),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.destination,
    required this.weight,
    required this.selected,
    required this.idle,
  });

  final NavDestination destination;

  /// 1 while the pill is on this destination, 0 once it is a whole destination
  /// away. Everything below is interpolated against it.
  final double weight;

  final Color selected;
  final Color idle;

  @override
  Widget build(BuildContext context) {
    final colour = Color.lerp(idle, selected, weight)!;

    return Transform.scale(
      scale: 1 + weight * 0.06,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(destination.icon, size: 22, color: colour),
          const SizedBox(height: 3),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1,
              color: colour,
              fontWeight: FontWeight.lerp(
                FontWeight.w500,
                FontWeight.w700,
                weight,
              ),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
