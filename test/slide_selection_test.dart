import 'package:flutter_test/flutter_test.dart';
import 'package:smart_arm_controller/widgets/slide_selection.dart';

/// The nav bar loses its Track destination when the arm outgrows hand tracking,
/// so the number of slots changes while the control is alive. Everything about
/// the pill - its width, its drag clamp, the slot it settles on - is derived
/// from that number.
void main() {
  test('shrinking pulls the pill off a slot that no longer exists', () {
    final selection =
        SlideSelection(vsync: const TestVSync(), count: 5, initial: 4);
    addTearDown(selection.dispose);

    expect(selection.index, 4);

    selection.count = 4;

    expect(selection.count, 4);
    expect(selection.index, 3, reason: 'left selecting a destination that is gone');
    expect(selection.position, lessThanOrEqualTo(3.0),
        reason: 'the pill is sitting past the end of the bar');
  });

  test('shrinking leaves a selection that still fits alone', () {
    final selection =
        SlideSelection(vsync: const TestVSync(), count: 5, initial: 1);
    addTearDown(selection.dispose);

    selection.count = 4;

    expect(selection.index, 1);
    expect(selection.position, 1.0);
  });

  test('growing makes room without moving anything', () {
    final selection =
        SlideSelection(vsync: const TestVSync(), count: 4, initial: 3);
    addTearDown(selection.dispose);

    selection.count = 5;

    expect(selection.count, 5);
    expect(selection.index, 3);
    expect(selection.position, 3.0);
  });

  test('refuses a bar with no destinations at all', () {
    final selection =
        SlideSelection(vsync: const TestVSync(), count: 4, initial: 2);
    addTearDown(selection.dispose);

    selection.count = 0;

    expect(selection.count, 4, reason: 'a bar with no slots cannot be drawn');
  });
}
