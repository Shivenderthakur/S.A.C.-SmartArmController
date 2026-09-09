import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// A selection that is allowed to sit *between* its options.
///
/// Tap and drag share one number: [position] is the selected index, but as a
/// double, so the pill under the thumb is never quantised and everything either
/// side of it — colour, scale, label weight — can be interpolated against it.
/// A release hands off to a critically damped spring carrying the fling
/// velocity, which is the part that reads as iOS rather than as a 200 ms ease.
class SlideSelection extends ChangeNotifier {
  SlideSelection({
    required TickerProvider vsync,
    required this.count,
    this.onChanged,
    int initial = 0,
  })  : _anim = AnimationController.unbounded(
          vsync: vsync,
          value: initial.toDouble(),
        ),
        _detent = initial {
    _anim.addListener(notifyListeners);
  }

  /// Stiff, and just short of overshooting: a bounce here would read as a toy.
  static final _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 1);

  final int count;
  final ValueChanged<int>? onChanged;
  final AnimationController _anim;

  bool _dragging = false;
  int _detent;

  /// Where the pill actually is, in destinations. 1.5 is halfway between the
  /// second and the third.
  double get position => _anim.value;

  /// The destination that is selected — the one a release would land on.
  int get index => _detent;

  bool get dragging => _dragging;

  /// How far off a detent the pill is: 0 at rest, 1 exactly between two.
  double get travel => (position - position.round()).abs() * 2;

  /// Weight for [i], 1 when the pill is on it and 0 once it is a full
  /// destination away. What the icons and labels animate against.
  double weightFor(int i) => (1 - (position - i).abs()).clamp(0.0, 1.0);

  void begin() {
    _dragging = true;
    _anim.stop();
    notifyListeners();
  }

  /// Follow the finger, but not rigidly.
  ///
  /// Snapping straight onto [target] makes a drag that starts away from the
  /// pill look like a teleport, and passes every twitch of the finger straight
  /// through. Closing a fraction of the gap per frame catches up in about four
  /// frames and then tracks one to one with a little weight behind it.
  void dragTo(double target, {double follow = 0.45}) {
    final next = position + (target - position) * follow;
    _anim.value = next.clamp(0, (count - 1).toDouble());
    _detentTo(position.round());
  }

  /// [velocity] in destinations per second.
  void end(double velocity) {
    _dragging = false;
    final target = (position + velocity * 0.14).round().clamp(0, count - 1);
    _settle(target, velocity);
  }

  void select(int target) => _settle(target.clamp(0, count - 1), 0);

  void cancel() {
    _dragging = false;
    _settle(_detent, 0);
  }

  void _settle(int target, double velocity) {
    _detentTo(target);
    _anim.animateWith(
      SpringSimulation(_spring, position, target.toDouble(), velocity),
    );
  }

  void _detentTo(int next) {
    if (next == _detent) return;
    _detent = next;
    // A click at each boundary, so a scrub can be felt without looking.
    HapticFeedback.selectionClick();
    onChanged?.call(next);
    notifyListeners();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }
}

/// Turns horizontal gestures over a row of [count] equal cells into calls on
/// [selection]. Shared by the nav bar and the segmented control so the two feel
/// like the same control at different sizes.
class SlideSelectionDetector extends StatelessWidget {
  const SlideSelectionDetector({
    super.key,
    required this.selection,
    required this.padding,
    required this.child,
  });

  final SlideSelection selection;

  /// Horizontal inset of the cells inside this widget.
  final double padding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final each =
            (constraints.maxWidth - padding * 2) / selection.count;

        double slotAt(double dx) => (dx - padding) / each - 0.5;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => selection.select(slotAt(d.localPosition.dx).round()),
          onHorizontalDragStart: (d) {
            selection.begin();
            selection.dragTo(slotAt(d.localPosition.dx), follow: 0.3);
          },
          onHorizontalDragUpdate: (d) =>
              selection.dragTo(slotAt(d.localPosition.dx)),
          onHorizontalDragEnd: (d) =>
              selection.end((d.primaryVelocity ?? 0) / each),
          onHorizontalDragCancel: selection.cancel,
          child: child,
        );
      },
    );
  }
}
