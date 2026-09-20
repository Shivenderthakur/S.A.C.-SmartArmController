import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_arm_controller/models/arm_step.dart';
import 'package:smart_arm_controller/services/arm_controller.dart';
import 'package:smart_arm_controller/services/arm_link.dart';
import 'package:smart_arm_controller/services/joint_config.dart';
import 'package:smart_arm_controller/services/sequence_player.dart';

/// Polls rather than sleeping a fixed time: the player runs on real timers.
Future<bool> waitFor(
  bool Function() until, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (until()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return until();
}

ArmStep step(String name, List<int> angles, {int speed = 600, int dwellMs = 0}) =>
    ArmStep(
      id: name,
      name: name,
      angles: angles,
      speed: speed,
      dwell: Duration(milliseconds: dwellMs),
    );

void main() {
  late ArmLink link;
  late ArmController arm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    link = ArmLink();
    arm = ArmController(link, await JointConfig.load());
  });

  tearDown(() {
    arm.dispose();
    link.dispose();
  });

  test('walks the arm to the pose rather than jumping to it', () async {
    final player = SequencePlayer(arm, tick: const Duration(milliseconds: 5));
    addTearDown(player.dispose);

    final seen = <List<int>>[];
    arm.addListener(() => seen.add(List<int>.of(arm.angles)));

    // Inside every joint's travel: the claw stops at 60 and the reach joint
    // starts at 10, and a pose outside that is clamped on the way through.
    player.play(ArmSequence(
      id: 's',
      name: 'one',
      gap: Duration.zero,
      steps: [step('a', [50, 50, 50, 50])],
    ));

    expect(await waitFor(() => !player.running), isTrue, reason: 'never finished');

    // The firmware ramps at its own rate and never says it arrived, so the
    // whole point is that the poses come out in pieces, not as one jump.
    expect(seen.length, greaterThan(3),
        reason: 'the step was sent as a single pose: ${seen.length} updates');
    expect(arm.angles.take(4), [50, 50, 50, 50]);
  });

  test('a slower step takes longer to get there', () async {
    Future<int> ticksFor(int speed) async {
      final player = SequencePlayer(arm, tick: const Duration(milliseconds: 5));
      addTearDown(player.dispose);
      arm.centre();

      var updates = 0;
      void count() => updates++;
      arm.addListener(count);

      player.play(ArmSequence(
        id: 's',
        name: 'one',
        gap: Duration.zero,
        steps: [step('a', [0, 0, 0, 0], speed: speed)],
      ));
      await waitFor(() => !player.running);
      arm.removeListener(count);
      return updates;
    }

    final quick = await ticksFor(900);
    final slow = await ticksFor(150);

    expect(slow, greaterThan(quick),
        reason: 'speed made no difference: $slow vs $quick');
  });

  test('holds each pose, then waits before the next step', () async {
    final player = SequencePlayer(arm, tick: const Duration(milliseconds: 5));
    addTearDown(player.dispose);

    player.play(ArmSequence(
      id: 's',
      name: 'two',
      gap: const Duration(milliseconds: 40),
      steps: [
        step('a', [10, 10, 10, 10], dwellMs: 40),
        step('b', [20, 20, 20, 20], dwellMs: 40),
      ],
    ));

    expect(await waitFor(() => player.phase == PlayPhase.dwelling), isTrue,
        reason: 'never held the first pose');
    expect(await waitFor(() => player.phase == PlayPhase.gap), isTrue,
        reason: 'never waited between steps');
    expect(await waitFor(() => player.stepIndex == 1), isTrue,
        reason: 'never reached the second step');
    expect(await waitFor(() => !player.running), isTrue);
    expect(arm.angles.take(4), [20, 20, 20, 20]);
  });

  test('loops back to the top, and stops when told', () async {
    final player = SequencePlayer(arm, tick: const Duration(milliseconds: 5));
    addTearDown(player.dispose);

    player.play(ArmSequence(
      id: 's',
      name: 'round',
      gap: Duration.zero,
      loop: true,
      steps: [step('a', [10, 10, 10, 10]), step('b', [20, 20, 20, 20])],
    ));

    expect(await waitFor(() => player.stepIndex == 1), isTrue);
    expect(await waitFor(() => player.stepIndex == 0), isTrue,
        reason: 'did not come back round');

    player.stop();
    expect(player.running, isFalse);
  });

  test('an empty routine does nothing at all', () {
    final player = SequencePlayer(arm, tick: const Duration(milliseconds: 5));
    addTearDown(player.dispose);

    player.play(ArmSequence(id: 's', name: 'empty', steps: const []));

    expect(player.running, isFalse);
  });
}
