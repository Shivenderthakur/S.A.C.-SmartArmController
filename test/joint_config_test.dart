import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_arm_controller/models/joint.dart';
import 'package:smart_arm_controller/services/joint_config.dart';

Future<JointConfig> freshConfig([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  return JointConfig.load();
}

void main() {
  test('starts as the arm the app has always driven', () async {
    final config = await freshConfig();

    // Three joints and a gripper, five servos: the gripper closes with two.
    expect(config.armJoints, 3);
    expect(config.hasGripper, isTrue);
    expect(config.channels, 4);
    expect(config.servos, 5);
    expect(config.pinMap, [16, 17, 18, 19, 21]);
    expect(config.trackingUsable, isTrue);
  });

  test('the claw\'s second servo gets the opposite angle', () async {
    final config = await freshConfig();

    // Joints first, then the mirrored halves, in the same order as the pin map
    // the board was told.
    expect(config.wireAngles([10, 20, 30, 40]), [10, 20, 30, 40, 140]);

    // Unwiring the second servo leaves the joint still expecting one: the
    // channel stays, with no pin behind it.
    config.unassign(3, mirror: true);
    expect(config.servos, 5);
    expect(config.pinMap, [16, 17, 18, 19, Joint.unassigned]);

    // Saying it has only one is what drops the channel.
    config.setTwoServos(3, false);
    expect(config.wireAngles([10, 20, 30, 40]), [10, 20, 30, 40]);
    expect(config.servos, 4);
  });

  test('a pin driving half a claw cannot drive anything else', () async {
    final config = await freshConfig();

    expect(config.ownerOf(21), 3, reason: 'the claw owns its second pin');
    expect(config.isMirrorPin(21), isTrue);
    expect(config.assign(0, 21), AssignResult.taken);
    expect(config.assign(3, 21), AssignResult.taken,
        reason: 'one pin cannot be both halves of the same claw');
  });

  test('refuses a pin that already drives another joint', () async {
    final config = await freshConfig();

    expect(config.assign(1, 16), AssignResult.taken);
    expect(config.pinMap[1], 17, reason: 'the refused pin was taken anyway');

    // 21 is the claw's second servo out of the box, so this takes a free one.
    expect(config.assign(1, 22), AssignResult.ok);
    expect(config.pinMap[1], 22);

    // The rest of the header is strapping pins, flash and the serial log.
    expect(config.assign(0, 99), AssignResult.notAllowed);
  });

  test('a fifth joint is beyond what the camera can drive', () async {
    final config = await freshConfig();
    expect(config.trackingUsable, isTrue);

    config.resize(5);

    // Five joints and the gripper still on the end.
    expect(config.channels, 6);
    expect(config.trackingUsable, isFalse);
    expect(config.joints.last.isGripper, isTrue);
    expect(config.joints.last.twoServos, isTrue);
    expect(config.servos, 7);
  });

  test('growing and shrinking keeps the joints that survive', () async {
    final config = await freshConfig();
    config.assign(0, 32);

    config.resize(6);
    expect(config.armJoints, 6);
    expect(config.channels, 7, reason: 'six joints and the gripper');
    expect(config.pinMap.first, 32, reason: 'an existing assignment was lost');

    final taken = config.pinMap.where((p) => p != Joint.unassigned).toList();
    expect(taken.every(allowedPins.contains), isTrue,
        reason: 'a servo landed on a pin that cannot drive one');
    expect(taken.toSet().length, taken.length,
        reason: 'two servos share a pin');

    config.resize(3);
    expect(config.armJoints, 3);
    expect(config.pinMap.first, 32);
    // Asking for fewer joints used to delete the thing on the end that grips.
    expect(config.hasGripper, isTrue,
        reason: 'shrinking the arm took the gripper with it');
    expect(config.joints.last.isGripper, isTrue);
    expect(config.channels, 4);
  });

  test('survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await JointConfig.load();
    first.resize(6);
    first.rename(5, 'Wrist');
    first.assign(5, 33);

    final second = await JointConfig.load();
    expect(second.channels, 7);
    expect(second.joints[5].name, 'Wrist');
    expect(second.joints[5].gpio, 33);
    expect(second.joints.last.isGripper, isTrue,
        reason: 'the gripper did not survive storage');
    expect(second.joints.last.twoServos, isTrue);
  });

  test('falls back to the default arm when the stored config is unreadable',
      () async {
    expect((await freshConfig({'joints_v1': 'not json at all'})).channels, 4);
    expect((await freshConfig({'joints_v1': '"a string"'})).channels, 4);
    expect((await freshConfig({'joints_v1': '{"v":1,"joints":[]}'})).channels, 4);
  });
}
