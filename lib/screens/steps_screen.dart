import 'package:flutter/material.dart';

import '../models/arm_step.dart';
import '../services/arm_controller.dart';
import '../services/sequence_player.dart';
import '../services/sequence_store.dart';
import '../widgets/glass.dart';
import '../widgets/joint_slider.dart';
import '../widgets/screen_body.dart';
import '../widgets/servo_slider.dart';

/// Teach the arm a routine: place it, keep that pose as a step, put the steps
/// in order, and play them back.
///
/// Everything here lives on the phone. The board is told nothing but poses, one
/// after another, down the link it already uses.
class StepsScreen extends StatefulWidget {
  const StepsScreen({
    super.key,
    required this.arm,
    required this.store,
    required this.player,
    this.trailing,
  });

  final ArmController arm;
  final SequenceStore store;
  final SequencePlayer player;
  final Widget? trailing;

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  String? _openId;

  ArmSequence get _routine {
    final at = _openId == null ? -1 : widget.store.indexOf(_openId!);
    return at < 0 ? widget.store.sequences.first : widget.store.sequenceAt(at);
  }

  void _use(ArmSequence routine) => setState(() => _openId = routine.id);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, widget.player]),
      builder: (context, _) {
        final routine = _routine;
        final playing = widget.player.running;

        return SliverScreenBody(
          kicker: 'Routine',
          title: 'Steps',
          trailing: widget.trailing,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Routines(
                    store: widget.store,
                    current: routine,
                    onPick: _use,
                  ),
                  const SizedBox(height: 12),
                  _Transport(
                    routine: routine,
                    player: widget.player,
                    onAdd: () => _addStep(routine),
                    onChanged: widget.store.replace,
                  ),
                  const SizedBox(height: 18),
                  GlassLabel(
                    routine.steps.isEmpty
                        ? 'No steps yet'
                        : '${routine.steps.length} steps, drag to reorder',
                  ),
                ],
              ),
            ),
            if (routine.steps.isEmpty)
              SliverToBoxAdapter(
                child: GlassCard(
                  child: Text(
                    'Press Add step: the sliders in front of you move the arm, '
                    'and what you leave it at is the step.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: context.glassMuted,
                    ),
                  ),
                ),
              )
            else
              SliverReorderableList(
                itemCount: routine.steps.length,
                onReorderItem: (from, to) =>
                    _use(widget.store.reorder(routine, from, to)),
                itemBuilder: (context, i) {
                  final step = routine.steps[i];
                  return _StepTile(
                    key: ValueKey(step.id),
                    index: i,
                    step: step,
                    running: playing && widget.player.stepIndex == i,
                    onEdit: () => _edit(routine, step),
                    onGoTo: () => widget.arm.setPose(step.angles),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  /// Place the arm, then keep it.
  ///
  /// The sliders here are the live ones: they drive the servos as they move, so
  /// the step is recorded from an arm already standing in the pose. One slider
  /// per joint, however many this arm has — a gripper's second servo follows
  /// its first and needs none.
  Future<void> _addStep(ArmSequence routine) async {
    final arm = widget.arm;
    final before = List<int>.of(arm.angles);
    final name = TextEditingController(
      text: 'Step ${routine.steps.length + 1}',
    );
    var speed = 60;
    var dwell = 400;
    var kept = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            child: GlassCard(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GlassLabel('Place the arm'),
                    Text(
                      'These move the servos as you drag them. Leave the arm '
                      'where the step should be.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.glassMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < arm.config.channels; i++) ...[
                      JointSlider(arm: arm, index: i),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    const GlassLabel('Name'),
                    TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 18),
                    _Dial(
                      label: 'Speed',
                      value: '$speed deg/s',
                      slider: ServoSlider(
                        value: speed.toDouble(),
                        min: ArmStep.minSpeed.toDouble(),
                        max: ArmStep.maxSpeed.toDouble(),
                        onChanged: (v) => setSheet(() => speed = v.round()),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Dial(
                      label: 'Hold here',
                      value: '${(dwell / 1000).toStringAsFixed(1)} s',
                      slider: ServoSlider(
                        value: dwell.toDouble(),
                        min: 0,
                        max: 5000,
                        onChanged: (v) => setSheet(() => dwell = v.round()),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: GlassButton(
                            label: 'Cancel',
                            icon: Icons.close,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassButton(
                            label: 'Save step',
                            icon: Icons.check,
                            filled: true,
                            onPressed: () {
                              kept = true;
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (kept) {
      var next = widget.store.record(routine, arm.angles);
      final added = next.steps.last;
      next = widget.store.replaceStep(
        next,
        added.copyWith(
          name: name.text.trim().isEmpty ? added.name : name.text.trim(),
          speed: speed,
          dwell: Duration(milliseconds: dwell),
        ),
      );
      _use(next);
    } else {
      // Cancelled: put the arm back rather than leaving it wherever the
      // sliders were abandoned.
      arm.setPose(before);
    }
    name.dispose();
  }

  Future<void> _edit(ArmSequence routine, ArmStep step) async {
    final name = TextEditingController(text: step.name);
    var speed = step.speed;
    var dwell = step.dwell.inMilliseconds;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GlassLabel('Name'),
                TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 18),
                _Dial(
                  label: 'Speed',
                  value: '$speed deg/s',
                  slider: ServoSlider(
                    value: speed.toDouble(),
                    min: ArmStep.minSpeed.toDouble(),
                    max: ArmStep.maxSpeed.toDouble(),
                    onChanged: (v) => setSheet(() => speed = v.round()),
                  ),
                ),
                const SizedBox(height: 14),
                _Dial(
                  label: 'Hold here',
                  value: '${(dwell / 1000).toStringAsFixed(1)} s',
                  slider: ServoSlider(
                    value: dwell.toDouble(),
                    min: 0,
                    max: 5000,
                    onChanged: (v) => setSheet(() => dwell = v.round()),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: 'Delete',
                        icon: Icons.delete_outline,
                        onPressed: () {
                          _use(widget.store.removeStep(routine, step.id));
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassButton(
                        label: 'Save',
                        icon: Icons.check,
                        filled: true,
                        onPressed: () {
                          _use(widget.store.replaceStep(
                            routine,
                            step.copyWith(
                              name: name.text.trim().isEmpty
                                  ? step.name
                                  : name.text.trim(),
                              speed: speed,
                              dwell: Duration(milliseconds: dwell),
                            ),
                          ));
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    name.dispose();
  }
}

/// The saved routines, and a way to start another.
class _Routines extends StatelessWidget {
  const _Routines({
    required this.store,
    required this.current,
    required this.onPick,
  });

  final SequenceStore store;
  final ArmSequence current;
  final ValueChanged<ArmSequence> onPick;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final routine in store.sequences)
          GestureDetector(
            onTap: () => onPick(routine),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: routine.id == current.id
                    ? accent.withValues(alpha: 0.2)
                    : context.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      routine.id == current.id ? accent : context.glassStroke,
                ),
              ),
              child: Text(
                '${routine.name} · ${routine.steps.length}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: () =>
              onPick(store.add(name: 'Routine ${store.sequences.length + 1}')),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.glassStroke),
            ),
            child: Icon(Icons.add, size: 18, color: context.glassMuted),
          ),
        ),
      ],
    );
  }
}

/// Add, play, and the two timings that belong to the whole routine.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.routine,
    required this.player,
    required this.onAdd,
    required this.onChanged,
  });

  final ArmSequence routine;
  final SequencePlayer player;
  final VoidCallback onAdd;
  final ValueChanged<ArmSequence> onChanged;

  @override
  Widget build(BuildContext context) {
    final playing = player.running;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Add step',
                  icon: Icons.add_circle_outline,
                  onPressed: playing ? null : onAdd,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  label: playing ? 'Stop' : 'Play',
                  icon: playing ? Icons.stop : Icons.play_arrow,
                  filled: !playing,
                  onPressed: routine.steps.isEmpty
                      ? null
                      : () => playing ? player.stop() : player.play(routine),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Dial(
            label: 'Wait between steps',
            value:
                '${(routine.gap.inMilliseconds / 1000).toStringAsFixed(1)} s',
            slider: ServoSlider(
              value: routine.gap.inMilliseconds.toDouble(),
              min: 0,
              max: 5000,
              onChanged: (v) => onChanged(
                routine.copyWith(gap: Duration(milliseconds: v.round())),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Repeat from the top',
                  style: TextStyle(fontSize: 13, color: context.glassMuted),
                ),
              ),
              Switch(
                value: routine.loop,
                onChanged: (v) => onChanged(routine.copyWith(loop: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({required this.label, required this.value, required this.slider});

  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: context.glassMuted),
              ),
            ),
            Text(
              value,
              style: monoStyle(
                size: 17,
                colour: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        slider,
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    super.key,
    required this.index,
    required this.step,
    required this.running,
    required this.onEdit,
    required this.onGoTo,
  });

  final int index;
  final ArmStep step;
  final bool running;
  final VoidCallback onEdit;
  final VoidCallback onGoTo;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        onTap: onEdit,
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: running ? accent : context.glassWell,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: monoStyle(
                  size: 12,
                  colour: running ? Colors.white : context.glassMuted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.angles.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 11, colour: context.glassMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${step.speed}°/s · ${(step.dwell.inMilliseconds / 1000).toStringAsFixed(1)}s',
              style: TextStyle(fontSize: 11, color: context.glassMuted),
            ),
            IconButton(
              onPressed: onGoTo,
              tooltip: 'Move the arm here',
              icon:
                  Icon(Icons.my_location, size: 18, color: context.glassMuted),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, color: context.glassMuted),
            ),
          ],
        ),
      ),
    );
  }
}
