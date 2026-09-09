import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';

/// The channel slider.
///
/// Tracking writes to this at frame rate, so the fill is drawn straight from
/// the value with no implicit animation in the way — an angle must never lag
/// the arm. Only the thumb animates, and only in response to the finger: it
/// swells on contact and settles back on release, which is the whole of what
/// makes an iOS slider feel gripped.
///
/// A null [onChanged] makes it a readout: same bar, no touch target, no thumb
/// shadow.
class ServoSlider extends StatefulWidget {
  const ServoSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.height = 34,
  });

  final double value, min, max, height;
  final ValueChanged<double>? onChanged;

  @override
  State<ServoSlider> createState() => _ServoSliderState();
}

class _ServoSliderState extends State<ServoSlider> {
  static const _thumb = 26.0;
  static const _grabbed = 30.0;

  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final live = widget.onChanged != null;
    final size = _dragging ? _grabbed : _thumb;

    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = constraints.maxWidth - _thumb;
        final pct = ((widget.value - widget.min) /
                (widget.max - widget.min))
            .clamp(0.0, 1.0);

        void update(Offset local) {
          final onChanged = widget.onChanged;
          if (onChanged == null) return;
          final p = ((local.dx - _thumb / 2) / travel).clamp(0.0, 1.0);
          onChanged(widget.min + p * (widget.max - widget.min));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition),
          // Horizontal rather than pan: these sit in a scrolling list, and a
          // pan recogniser would win the arena on a vertical drag and eat the
          // scroll.
          onHorizontalDragStart: (d) {
            if (!live) return;
            setState(() => _dragging = true);
            HapticFeedback.selectionClick();
            update(d.localPosition);
          },
          onHorizontalDragUpdate: (d) => update(d.localPosition),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Track.
                Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: (context.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: context.isDark ? 0.14 : 0.09),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Fill, up to the middle of the thumb.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 8,
                      width: (pct * travel + _thumb / 2 - 2)
                          .clamp(0.0, constraints.maxWidth - 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.55),
                              accent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: pct * travel + (_thumb - size) / 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutBack,
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: accent.withValues(alpha: live ? 0.5 : 0.25),
                        width: 2,
                      ),
                      boxShadow: live
                          ? [
                              BoxShadow(
                                blurRadius: _dragging ? 14 : 8,
                                offset: const Offset(0, 3),
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
