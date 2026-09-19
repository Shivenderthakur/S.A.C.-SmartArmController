import 'package:flutter/material.dart';

import 'glass.dart';
import 'slide_selection.dart';

class Segment<T> {
  const Segment(this.value, this.icon, this.label);

  final T value;
  final IconData icon;
  final String label;
}

/// A segmented control you can drag, the way the iOS one has always worked.
///
/// Tapping a segment picks it; pressing and sliding carries the pill along with
/// the finger and commits at each boundary. It runs on the same
/// [SlideSelection] as the nav bar, so the two respond identically — same
/// follow, same spring, same haptic tick.
class GlassSegmented<T> extends StatefulWidget {
  const GlassSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  State<GlassSegmented<T>> createState() => _GlassSegmentedState<T>();
}

class _GlassSegmentedState<T> extends State<GlassSegmented<T>>
    with SingleTickerProviderStateMixin {
  static const _height = 52.0;
  static const _inset = 4.0;

  late final SlideSelection _selection = SlideSelection(
    vsync: this,
    count: widget.segments.length,
    initial: _indexOf(widget.value),
    onChanged: (i) => widget.onChanged(widget.segments[i].value),
  );

  int _indexOf(T value) {
    final i = widget.segments.indexWhere((s) => s.value == value);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(GlassSegmented<T> old) {
    super.didUpdateWidget(old);
    // The number of segments can change under us, and the pill's width and its
    // drag clamp are both derived from it.
    _selection.count = widget.segments.length;
    // Somewhere else changed the value — follow it, with the same spring.
    final target = _indexOf(widget.value);
    if (target != _selection.index) _selection.select(target);
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final idle = context.glassMuted;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: context.glassWell,
        borderRadius: BorderRadius.circular(_height / 2),
        border: Border.all(
          color: (context.isDark ? Colors.white : Colors.black)
              .withValues(alpha: 0.08),
        ),
      ),
      child: SlideSelectionDetector(
        selection: _selection,
        padding: _inset,
        child: AnimatedBuilder(
          animation: _selection,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final each =
                  (constraints.maxWidth - _inset * 2) / widget.segments.length;

              return Stack(
                children: [
                  Positioned(
                    left: _inset + _selection.position * each,
                    top: _inset,
                    bottom: _inset,
                    width: each,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: accent.withValues(
                          alpha: context.isDark ? 0.34 : 0.26,
                        ),
                        borderRadius: BorderRadius.circular(_height / 2),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                            color: Colors.black.withValues(
                              alpha: context.isDark ? 0.3 : 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: _inset),
                      for (var i = 0; i < widget.segments.length; i++)
                        SizedBox(
                          width: each,
                          child: _Segment(
                            segment: widget.segments[i],
                            weight: _selection.weightFor(i),
                            selected: onSurface,
                            idle: idle,
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
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.weight,
    required this.selected,
    required this.idle,
  });

  final Segment segment;
  final double weight;
  final Color selected;
  final Color idle;

  @override
  Widget build(BuildContext context) {
    final colour = Color.lerp(idle, selected, weight)!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(segment.icon, size: 17, color: colour),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            segment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: colour,
              fontWeight:
                  FontWeight.lerp(FontWeight.w500, FontWeight.w700, weight),
            ),
          ),
        ),
      ],
    );
  }
}
