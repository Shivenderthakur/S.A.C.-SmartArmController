import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_arm_controller/models/board.dart';
import 'package:smart_arm_controller/models/joint.dart';
import 'package:smart_arm_controller/screens/board_screen.dart';
import 'package:smart_arm_controller/services/arm_link.dart';
import 'package:smart_arm_controller/services/joint_config.dart';

/// Pumps the Board screen with a five-joint arm whose first joint has no pin.
Future<JointConfig> pumpBoard(WidgetTester tester, {double textScale = 1}) async {
  // Tall enough for the board and both pin rails to be laid out at once.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final config = await JointConfig.load();
  config.resize(5);
  config.unassign(0);

  // Reading board.json is real I/O, and a widget test only lets that run inside
  // runAsync — so it is parsed here and handed over already loaded. Left to the
  // screen, the future never completes and the pin blocks never appear.
  final layout = await tester.runAsync(BoardLayout.load);

  final link = ArmLink();
  addTearDown(link.dispose);

  // A Scaffold, because refusing a drop raises a SnackBar and ScaffoldMessenger
  // needs one to present into — in the app the screen sits inside HomeShell's.
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: Scaffold(
        body: BoardScreen(config: config, link: link, layout: layout),
      ),
    ),
  ));
  await tester.pump();
  return config;
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: 'nothing on screen reads "$text"');
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump();
}

/// A joint's name is on its chip and again in the two-servo list, so a bare
/// find.text arms nothing - and the next tap on a pin then reads as "clear this
/// one" rather than "put that servo here".
Future<void> tapChip(WidgetTester tester, String name) async {
  final finder = find.descendant(
    of: find.byType(Draggable<ServoRef>),
    matching: find.text(name),
  );
  expect(finder, findsWidgets, reason: 'no servo chip reads "$name"');
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump();
}

void main() {
  testWidgets('shows a block for every pin that can carry a servo',
      (tester) async {
    await pumpBoard(tester);

    // Seven on the right header, two on the left.
    for (final pin in [16, 17, 18, 19, 21, 22, 23, 32, 33]) {
      expect(find.text('GP$pin'), findsOneWidget, reason: 'GPIO$pin is missing');
    }
    // And nothing for the pins that cannot drive a servo.
    expect(find.text('GP0'), findsNothing);
    expect(find.text('GP5'), findsNothing);
  });

  testWidgets('lays out at the largest text size the app allows',
      (tester) async {
    await pumpBoard(tester, textScale: 1.3);

    // An overflowing Row or Column throws, and the test framework hands it over
    // here rather than failing on its own.
    expect(tester.takeException(), isNull);
    expect(find.text('GP16'), findsOneWidget);
  });

  testWidgets('a loose joint can be tapped onto a free pin', (tester) async {
    final config = await pumpBoard(tester);
    // Whichever pin is actually spare: the claw takes two, so which one that is
    // depends on the arm.
    final free = allowedPins.firstWhere((p) => config.ownerOf(p) == null);

    await tapChip(tester, config.joints[0].name);
    await tapText(tester, 'GP$free');

    expect(config.joints[0].gpio, free);
  });

  testWidgets('a claw offers its second servo once it has two', (tester) async {
    final config = await pumpBoard(tester);
    final claw = config.joints.indexWhere((j) => j.twoServos);
    expect(claw, isNot(-1), reason: 'the default arm should have a two-servo claw');

    final name = config.joints[claw].name;
    final chips = find.descendant(
      of: find.byType(Draggable<ServoRef>),
      matching: find.textContaining(name),
    );

    // Only loose servos get a chip, so freeing the second pin offers exactly
    // that half - the first is still wired.
    config.unassign(claw, mirror: true);
    await tester.pump();
    expect(chips, findsOneWidget);
    expect(find.text('$name, 2nd'), findsOneWidget);

    // Free the other half and the claw offers both, as two separate servos.
    config.unassign(claw);
    await tester.pump();
    expect(chips, findsNWidgets(2));
    expect(find.text(name), findsWidgets);
  });

  testWidgets('a pin that already drives a joint refuses another',
      (tester) async {
    final config = await pumpBoard(tester);
    final taken = config.joints[1].gpio;

    await tapChip(tester, config.joints[0].name);
    await tapText(tester, 'GP$taken');

    expect(config.joints[0].assigned, isFalse,
        reason: 'the joint stole a pin that was already driving another');
    expect(config.joints[1].gpio, taken);
    expect(find.textContaining('already drives'), findsOneWidget,
        reason: 'the refusal was silent');

    // Let the SnackBar finish animating and time out, so no timer outlives the
    // test.
    await tester.pump(const Duration(seconds: 5));
  });
}
