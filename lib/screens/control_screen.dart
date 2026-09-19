import 'package:flutter/material.dart';

import '../models/arm_step.dart';
import '../services/arm_controller.dart';
import '../services/sequence_player.dart';
import '../services/sequence_store.dart';
import '../widgets/glass.dart';
import '../widgets/screen_body.dart';
import '../widgets/servo_slider.dart';

/// Drive the arm by hand, and teach it a routine.
///
/// The two belong together: a step is only ever the pose the sliders are
/// holding, so recording one is the same gesture as setting one. Touching a
/// slider switches the arm to manual, because otherwise the next tracked frame
/// would overwrite whatever was just set.
class ControlScreen extends StatefulWidget {
  const ControlScreen({
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
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  String? _openId;

  ArmSequence get _routine {
    final at = _openId == null ? -1 : widget.store.indexOf(_openId!);
    return at < 0 ? widget.store.sequences.first : widget.store.sequenceAt(at);
  }

  void _use(ArmSequence routine) => setState(() => _openId = routine.id);

  @override
  Widget build(BuildContext context) {
    // Deliberately not listening to the arm here: its angles change twelve
    // times a second while streaming, and rebuilding the whole screen - every
    // slider, every step - at that rate is what made this feel heavy. Only the
    // one readout that shows an angle listens.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, widget.player]),
      builder: (context, _) {
        final routine = _routine;
        final playing = widget.player.running;

        return SliverScreenBody(
          kicker: 'Manual',
          title: 'Custom control',
          trailing: widget.trailing,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Mode(arm: widget.arm),
                  const SizedBox(height: 12),
                  for (var i = 0; i < widget.arm.config.channels; i++) ...[
                    _Channel(arm: widget.arm, index: i),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          label: 'Centre all',
                          icon: Icons.center_focus_strong_outlined,
                          onPressed: playing ? null : widget.arm.centre,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassButton(
                          label: 'Back to hand',
                          icon: Icons.videocam_outlined,
                          onPressed: widget.arm.config.trackingUsable && !playing
                              ? () => widget.arm.manual = false
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Routines(
                    store: widget.store,
                    current: routine,
                    onPick: _use,
                  ),
                  const SizedBox(height: 12),
                  _Transport(
                    routine: routine,
                    player: widget.player,
                    onRecord: () =>
                        _use(widget.store.record(routine, widget.arm.angles)),
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
                    'Put the arm where you want it with the sliders above, then '
                    'press Record. A step remembers every joint at once.',
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

/// Whether the sliders or the camera are driving, and why.
class _Mode extends StatelessWidget {
  const _Mode({required this.arm});

  final ArmController arm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: arm,
      builder: (context, _) {
        final tracked = arm.config.trackingUsable;

        return GlassCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            children: [
              Icon(
                arm.manual ? Icons.pan_tool : Icons.waving_hand_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      arm.manual ? 'Manual control' : 'Hand tracking',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !tracked
                          ? 'This arm has more joints than the camera can '
                              'drive, so the sliders and the steps below are '
                              'the way to move it.'
                          : arm.manual
                              ? 'The sliders drive the arm. Tracking still runs '
                                  'but is ignored.'
                              : 'The camera drives the arm. Move a slider to '
                                  'take over.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: context.glassMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (tracked)
                Switch(
                  value: arm.manual,
                  onChanged: (v) => arm.manual = v,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One joint. Listens to the arm on its own so a moving angle repaints a card
/// rather than the screen.
class _Channel extends StatelessWidget {
  const _Channel({required this.arm, required this.index});

  final ArmController arm;
  final int index;

  @override
  Widget build(BuildContext context) {
    final joint = arm.config.joints[index];
    final accent = Theme.of(context).colorScheme.primary;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      joint.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${joint.min} to ${joint.max} degrees',
                      style: TextStyle(fontSize: 12, color: context.glassMuted),
                    ),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: arm,
                builder: (context, _) => Text(
                  '${arm.angles[index]}',
                  style: monoStyle(size: 26, colour: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: arm,
            builder: (context, _) => ServoSlider(
              value: arm.angles[index].toDouble(),
              min: joint.min.toDouble(),
              max: joint.max.toDouble(),
              onChanged: (v) => arm.setChannel(index, v.round()),
            ),
          ),
        ],
      ),
    );
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

/// Record, play, and the two timings that belong to the whole routine.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.routine,
    required this.player,
    required this.onRecord,
    required this.onChanged,
  });

  final ArmSequence routine;
  final SequencePlayer player;
  final VoidCallback onRecord;
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
                  label: 'Record',
                  icon: Icons.fiber_manual_record_outlined,
                  onPressed: playing ? null : onRecord,
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
