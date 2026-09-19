import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/arm_step.dart';

/// The saved sequences, on the phone.
///
/// Nothing is uploaded to the board: it holds no map of its own and no memory
/// beyond the pose it is walking toward, so playback is the app streaming poses
/// down the same link everything else uses.
class SequenceStore extends ChangeNotifier {
  SequenceStore._(this._prefs, this._sequences);

  static const _key = 'sequences_v1';

  final SharedPreferences _prefs;
  final List<ArmSequence> _sequences;

  static Future<SequenceStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SequenceStore._(prefs, _read(prefs));
  }

  static List<ArmSequence> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return [ArmSequence.empty()];
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final list = [
        for (final s in (decoded['sequences'] as List<Object?>? ?? []))
          ArmSequence.fromJson(s as Map<String, Object?>),
      ];
      return list.isEmpty ? [ArmSequence.empty()] : list;
    } catch (_) {
      // Unreadable, hand-edited, or from a version that knew more: losing the
      // sequences is bad, failing to launch is worse.
      return [ArmSequence.empty()];
    }
  }

  List<ArmSequence> get sequences => List<ArmSequence>.unmodifiable(_sequences);

  ArmSequence sequenceAt(int index) => _sequences[index];

  int indexOf(String id) => _sequences.indexWhere((s) => s.id == id);

  void replace(ArmSequence sequence) {
    final at = indexOf(sequence.id);
    if (at < 0) return;
    _sequences[at] = sequence;
    _save();
  }

  ArmSequence add({String name = 'Sequence'}) {
    final made = ArmSequence(id: ArmStep.newId(), name: name, steps: const []);
    _sequences.add(made);
    _save();
    return made;
  }

  void remove(String id) {
    if (_sequences.length == 1) {
      // Always leave one to record into, rather than an empty screen with no
      // obvious way forward.
      _sequences[0] = ArmSequence.empty();
    } else {
      _sequences.removeWhere((s) => s.id == id);
    }
    _save();
  }

  /// Appends the arm's current pose as a new step.
  ArmSequence record(ArmSequence into, List<int> angles) {
    final steps = [
      ...into.steps,
      ArmStep(
        id: ArmStep.newId(),
        name: 'Step ${into.steps.length + 1}',
        angles: List<int>.of(angles),
      ),
    ];
    final next = into.copyWith(steps: steps);
    replace(next);
    return next;
  }

  ArmSequence removeStep(ArmSequence from, String stepId) {
    final next = from.copyWith(
      steps: [for (final s in from.steps) if (s.id != stepId) s],
    );
    replace(next);
    return next;
  }

  ArmSequence replaceStep(ArmSequence inside, ArmStep step) {
    final next = inside.copyWith(
      steps: [for (final s in inside.steps) if (s.id == step.id) step else s],
    );
    replace(next);
    return next;
  }

  /// Drag-and-drop reorder. [to] is where the step lands once it has been
  /// lifted out — the index SliverReorderableList's onReorderItem gives, which
  /// is already adjusted for the gap the row left behind.
  ArmSequence reorder(ArmSequence inside, int from, int to) {
    final steps = List<ArmStep>.of(inside.steps);
    if (from < 0 || from >= steps.length) return inside;

    final moved = steps.removeAt(from);
    steps.insert(to.clamp(0, steps.length), moved);

    final next = inside.copyWith(steps: steps);
    replace(next);
    return next;
  }

  void _save() {
    _prefs.setString(
      _key,
      jsonEncode({
        'v': 1,
        'sequences': [for (final s in _sequences) s.toJson()],
      }),
    );
    notifyListeners();
  }
}
