import 'package:flutter/foundation.dart';

import '../models/hand.dart';
import 'arm_link.dart';

/// The four servo angles, wherever they came from.
///
/// Hand tracking and the manual sliders both write here, and this is the only
/// thing that talks to [ArmLink] - so whatever is on screen is what the arm was
/// told, with no second path to keep in sync.
class ArmController extends ChangeNotifier {
  ArmController(this.link);

  final ArmLink link;

  List<int> _angles = List<int>.of(servoRest);
  bool _manual = false;

  /// The same angles as a [ValueListenable], for the overlay painter's
  /// `repaint:` - it must not rebuild a widget to redraw at frame rate.
  final anglesListenable = ValueNotifier<List<int>>(List<int>.of(servoRest));

  List<int> get angles => _angles;

  /// While manual, hand tracking still runs and draws, but stops driving the
  /// arm. Otherwise the two sources would fight over every frame.
  bool get manual => _manual;
  set manual(bool v) {
    if (_manual == v) return;
    _manual = v;
    notifyListeners();
  }

  void fromHand(List<int> next) {
    if (_manual) return;
    _apply(next);
  }

  void setChannel(int index, int value) {
    final next = List<int>.of(_angles);
    final (min, max) = servoRanges[index];
    next[index] = value.clamp(min, max);
    _manual = true;
    _apply(next);
  }

  void centre() {
    _manual = true;
    _apply(List<int>.of(servoRest));
  }

  void _apply(List<int> next) {
    if (listEquals(next, _angles)) return;
    _angles = next;
    anglesListenable.value = next;
    // The desktop script only wrote to the port when a value changed.
    link.send(next);
    notifyListeners();
  }

  @override
  void dispose() {
    anglesListenable.dispose();
    super.dispose();
  }
}
