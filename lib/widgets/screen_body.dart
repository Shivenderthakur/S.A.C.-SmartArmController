import 'package:flutter/material.dart';

import 'glass.dart';
import 'slide_nav_bar.dart';

/// The shape every screen takes: a kicker, a big title and a scrolling column
/// of glass, with room left at the bottom for the floating nav bar to sit over.
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.kicker,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String kicker;
  final String title;

  /// The link status, carried on every screen — there is no app bar to put it
  /// in any more.
  final Widget? trailing;

  final List<Widget> children;

  /// The insets every screen shares: clear of the status bar at the top, and of
  /// the floating nav bar, its inset and the gesture area at the bottom.
  static EdgeInsets insets(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      20,
      padding.top + 28,
      20,
      // Clear of the bar, its inset, the gesture area - and then some. Landing
      // a card's last line exactly against the bar reads as clipped rather
      // than as something to scroll past.
      padding.bottom + SlideNavBar.height + 72,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: insets(context),
      children: [
        ScreenHeader(kicker: kicker, title: title, trailing: trailing),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

/// The same screen, for content that has to be slivers.
///
/// A reorderable list cannot live inside the [ScreenBody] above - that is a
/// ListView, and a list inside a list has no height to work with - so a screen
/// that drags its rows around builds itself out of slivers instead, sharing
/// this header and these insets so it still looks like every other screen.
class SliverScreenBody extends StatelessWidget {
  const SliverScreenBody({
    super.key,
    required this.kicker,
    required this.title,
    required this.slivers,
    this.trailing,
  });

  final String kicker;
  final String title;
  final Widget? trailing;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: ScreenBody.insets(context).copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ScreenHeader(
                kicker: kicker,
                title: title,
                trailing: trailing,
              ),
            ),
          ),
        ),
        ...slivers,
        SliverToBoxAdapter(
          child: SizedBox(height: ScreenBody.insets(context).bottom),
        ),
      ],
    );
  }
}

/// The kicker and big title every screen opens with.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.kicker,
    required this.title,
    this.trailing,
  });

  final String kicker;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kicker.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.7,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8),
            child: trailing,
          ),
      ],
    );
  }
}

/// A row of two buttons, the pair every screen ends with.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final enabled = onPressed != null;
    final foreground = filled
        ? (ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black)
        : Theme.of(context).colorScheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? accent : context.glassFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: filled ? accent : context.glassStroke,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
