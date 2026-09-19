import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_arm_controller/services/sequence_store.dart';

Future<SequenceStore> freshStore([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  return SequenceStore.load();
}

void main() {
  test('opens with one empty routine to record into', () async {
    final store = await freshStore();

    expect(store.sequences, hasLength(1));
    expect(store.sequences.first.steps, isEmpty);
  });

  test('recording appends the pose the arm is in', () async {
    final store = await freshStore();

    var routine = store.record(store.sequences.first, [10, 20, 30, 40]);
    routine = store.record(routine, [50, 60, 70, 20]);

    expect(routine.steps, hasLength(2));
    expect(routine.steps.first.angles, [10, 20, 30, 40]);
    expect(routine.steps.last.angles, [50, 60, 70, 20]);
    expect(routine.steps.map((s) => s.id).toSet(), hasLength(2),
        reason: 'two steps share an id, so the list cannot key them apart');
  });

  test('reorder takes the index the row lands on once it is lifted out',
      () async {
    final store = await freshStore();
    var routine = store.sequences.first;
    for (final pose in [
      [1, 1, 1, 1],
      [2, 2, 2, 2],
      [3, 3, 3, 3],
    ]) {
      routine = store.record(routine, pose);
    }

    // Dragging the first row to the end: SliverReorderableList's onReorderItem
    // has already accounted for the gap it left behind.
    routine = store.reorder(routine, 0, 2);

    expect([for (final s in routine.steps) s.angles.first], [2, 3, 1]);
  });

  test('an edited step keeps its place', () async {
    final store = await freshStore();
    var routine = store.record(store.sequences.first, [5, 5, 5, 5]);
    routine = store.record(routine, [6, 6, 6, 6]);

    final second = routine.steps[1];
    routine = store.replaceStep(
      routine,
      second.copyWith(name: 'Pick up', speed: 90),
    );

    expect(routine.steps[1].name, 'Pick up');
    expect(routine.steps[1].speed, 90);
    expect(routine.steps[0].angles, [5, 5, 5, 5]);
  });

  test('deleting a step leaves the rest alone', () async {
    final store = await freshStore();
    var routine = store.record(store.sequences.first, [1, 1, 1, 1]);
    routine = store.record(routine, [2, 2, 2, 2]);

    routine = store.removeStep(routine, routine.steps.first.id);

    expect(routine.steps, hasLength(1));
    expect(routine.steps.single.angles, [2, 2, 2, 2]);
  });

  test('the last routine is emptied rather than removed', () async {
    final store = await freshStore();
    final only = store.record(store.sequences.first, [9, 9, 9, 9]);

    store.remove(only.id);

    expect(store.sequences, hasLength(1),
        reason: 'an empty screen with no way to start again');
    expect(store.sequences.first.steps, isEmpty);
  });

  test('survives a restart, timings and all', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await SequenceStore.load();
    var routine = first.record(first.sequences.first, [11, 22, 33, 44]);
    routine = first.replaceStep(
      routine,
      routine.steps.single.copyWith(
        name: 'Home',
        speed: 75,
        dwell: const Duration(milliseconds: 1200),
      ),
    );
    first.replace(routine.copyWith(
      name: 'Pick and place',
      gap: const Duration(milliseconds: 800),
      loop: true,
    ));

    final second = await SequenceStore.load();
    final saved = second.sequences.single;

    expect(saved.name, 'Pick and place');
    expect(saved.gap, const Duration(milliseconds: 800));
    expect(saved.loop, isTrue);
    expect(saved.steps.single.name, 'Home');
    expect(saved.steps.single.speed, 75);
    expect(saved.steps.single.dwell, const Duration(milliseconds: 1200));
    expect(saved.steps.single.angles, [11, 22, 33, 44]);
  });

  test('falls back to an empty routine when what is stored is unreadable',
      () async {
    expect((await freshStore({'sequences_v1': 'not json'})).sequences, hasLength(1));
    expect((await freshStore({'sequences_v1': '[]'})).sequences, hasLength(1));
    expect(
      (await freshStore({'sequences_v1': '{"v":1,"sequences":[]}'})).sequences,
      hasLength(1),
    );
  });
}
