import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_arm_controller/screens/steps_screen.dart';
import 'package:smart_arm_controller/services/arm_controller.dart';
import 'package:smart_arm_controller/services/arm_link.dart';
import 'package:smart_arm_controller/services/joint_config.dart';
import 'package:smart_arm_controller/services/sequence_player.dart';
import 'package:smart_arm_controller/services/sequence_store.dart';
import 'package:smart_arm_controller/widgets/joint_slider.dart';

/// A step is a pose, so both sheets that make one have to offer the arm itself
/// - a slider per joint, live. Editing one could change its name and its
/// timings but not where it went, which is most of what a step is.
class Harness {
  Harness(this.arm, this.store, this.player);

  final ArmController arm;
  final SequenceStore store;
  final SequencePlayer player;
}

Future<Harness> pumpSteps(WidgetTester tester, {bool withStep = true}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final config = await JointConfig.load();
  final link = ArmLink();
  addTearDown(link.dispose);
  final arm = ArmController(link, config);
  addTearDown(arm.dispose);
  final store = await SequenceStore.load();
  final player = SequencePlayer(arm);
  addTearDown(player.dispose);

  if (withStep) store.record(store.sequences.first, arm.angles);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StepsScreen(arm: arm, store: store, player: player),
    ),
  ));
  await tester.pump();
  return Harness(arm, store, player);
}

void main() {
  testWidgets('editing a step offers the arm, not just its name',
      (tester) async {
    final h = await pumpSteps(tester);

    expect(find.byType(JointSlider), findsNothing,
        reason: 'the sliders belong in the sheet, not the list');

    await tester.tap(find.text('Step 1'));
    await tester.pumpAndSettle();

    // One live slider per joint, however many this arm has.
    expect(find.byType(JointSlider), findsNWidgets(h.arm.config.channels));
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('adding a step offers them too', (tester) async {
    final h = await pumpSteps(tester, withStep: false);

    await tester.tap(find.text('Add step'));
    await tester.pumpAndSettle();

    expect(find.byType(JointSlider), findsNWidgets(h.arm.config.channels));
    expect(find.text('Save step'), findsOneWidget);
  });

  testWidgets('a routine can be thrown away', (tester) async {
    final h = await pumpSteps(tester, withStep: false);
    h.store.add(name: 'Second');
    await tester.pump();

    final open = h.store.sequences.first;
    expect(find.textContaining(open.name), findsOneWidget);

    // Only the open routine carries a cross, and an empty one goes without
    // being asked about.
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(h.store.sequences.map((s) => s.id), isNot(contains(open.id)));
  });
}
