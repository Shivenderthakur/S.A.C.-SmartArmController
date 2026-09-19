import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/arm_step.dart';
import 'arm_controller.dart';

enum PlayPhase { moving, dwelling, gap }

/// Walks a sequence, one pose at a time.
///
/// The interpolation is deliberately done here rather than on the board. The
/// firmware ramps at its own fixed rate with no speed control and no signal
/// that a joint has arrived, so if a whole step were sent as one pose the
/// timing would be the firmware's, not the step's. Sending a pose a degree or
/// two along every tick leaves the firmware's ramp nothing to do and puts this
/// timeline in charge - which is what makes a step's speed mean anything.
///
/// It stays open loop: dwell and gap are measured from the last pose *sent*,
/// not from a servo arriving, and a stalled joint lags without saying so.
class SequencePlayer extends ChangeNotifier {
  SequencePlayer(this.arm, {this.tick = const Duration(milliseconds: 50)});

  final ArmController arm;

  /// How often a pose goes out. Also the clock: elapsed time is counted in
  /// ticks, so a test can run a sequence far faster than real time.
  final Duration tick;

  Timer? _timer;
  ArmSequence? _sequence;
  int _index = 0;
  PlayPhase _phase = PlayPhase.moving;
  List<int> _from = const [];
  Duration _elapsed = Duration.zero;

  bool get running => _timer != null;
  int get stepIndex => _index;
  PlayPhase get phase => _phase;
  ArmSequence? get sequence => _sequence;

  void play(ArmSequence sequence) {
    if (sequence.steps.isEmpty) return;
    _timer?.cancel();

    _sequence = sequence;
    _index = 0;
    _beginStep();
    _timer = Timer.periodic(tick, (_) => _advance());
    notifyListeners();
  }

  void stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    notifyListeners();
  }

  void _beginStep() {
    _from = List<int>.of(arm.angles);
    _elapsed = Duration.zero;
    _phase = PlayPhase.moving;
  }

  /// The furthest any one joint has to travel, at this step's speed. Joints
  /// move together, so the slowest one sets the pace.
  Duration _moveDuration(ArmStep step) {
    var furthest = 0;
    for (var i = 0; i < step.angles.length && i < _from.length; i++) {
      final travel = (step.angles[i] - _from[i]).abs();
      if (travel > furthest) furthest = travel;
    }
    if (furthest == 0) return Duration.zero;
    return Duration(milliseconds: (furthest / step.speed * 1000).round());
  }

  void _advance() {
    final sequence = _sequence;
    if (sequence == null || _index >= sequence.steps.length) {
      stop();
      return;
    }

    final step = sequence.steps[_index];
    _elapsed += tick;

    if (_phase == PlayPhase.moving) {
      final total = _moveDuration(step);
      final t = total.inMilliseconds == 0
          ? 1.0
          : (_elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

      arm.setPose([
        for (var i = 0; i < step.angles.length; i++) _at(i, step.angles[i], t),
      ]);

      if (t >= 1) {
        _phase = PlayPhase.dwelling;
        _elapsed = Duration.zero;
      }
    } else if (_phase == PlayPhase.dwelling) {
      if (_elapsed >= step.dwell) {
        _phase = PlayPhase.gap;
        _elapsed = Duration.zero;
      }
    } else if (_elapsed >= sequence.gap) {
      _next(sequence);
    }

    notifyListeners();
  }

  int _at(int joint, int to, double t) {
    final from = joint < _from.length ? _from[joint] : to;
    return (from + (to - from) * t).round();
  }

  void _next(ArmSequence sequence) {
    final next = _index + 1;
    if (next >= sequence.steps.length) {
      if (!sequence.loop) {
        stop();
        return;
      }
      _index = 0;
    } else {
      _index = next;
    }
    _beginStep();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
