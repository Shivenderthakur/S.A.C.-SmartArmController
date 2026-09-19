import 'package:flutter/material.dart';

import '../models/arm_step.dart';
import '../services/arm_controller.dart';
import '../services/sequence_player.dart';
import '../services/sequence_store.dart';
import '../widgets/glass.dart';
import '../widgets/screen_body.dart';
import '../widgets/servo_slider.dart';

/// Teach the arm a routine: record where it is, name it, drag the steps into
/// order, and play them back.
///
/// Everything here lives on the phone. The board is told nothing but poses, one
/// after another, down the link it already uses.
class StepsScreen extends StatefulWidget {
  const StepsScreen({
    super.key,
    required this.store,
    required this.player,
    required this.arm,
    this.trailing,
  });

  final SequenceStore store;
  final SequencePlayer player;
  final ArmController arm;
  final Widget? trailing;

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  String? _openId;

  ArmSequence get _sequence {
    final at = _openId == null ? -1 : widget.store.indexOf(_openId!);
    return at < 0 ? widget.store.sequences.first : widget.store.sequenceAt(at);
  }

  void _use(ArmSequence sequence) => setState(() => _openId = sequence.id);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, widget.player, widget.arm]),
      builder: (context, _) {
        final sequence = _sequence;
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
                  _Sequences(
                    store: widget.store,
                    current: sequence,
                    onPick: _use,
                  ),
                  const SizedBox(height: 14),
                  _Transport(
                    sequence: sequence,
                    player: widget.player,
                    onRecord: () => _use(
                      widget.store.record(sequence, widget.arm.angles),
                    ),
                    onChanged: widget.store.replace,
                  ),
                  const SizedBox(height: 18),
                  GlassLabel(
                    sequence.steps.isEmpty
                        ? 'No steps yet'
                        : '${sequence.steps.length} steps, drag to reorder',
                  ),
                ],
              ),
            ),
            if (sequence.steps.isEmpty)
              SliverToBoxAdapter(
                child: GlassCard(
                  child: Text(
                    'Move the arm where you want it — on the Control screen, or '
                    'with your hand — then press Record. Each step remembers '
                    'every joint.',
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
                itemCount: sequence.steps.length,
                // onReorderItem, not onReorder: it hands back an index that
                // already accounts for the row being lifted out.
                onReorderItem: (from, to) =>
                    _use(widget.store.reorder(sequence, from, to)),
                itemBuilder: (context, i) {
                  final step = sequence.steps[i];
                  return _StepTile(
                    key: ValueKey(step.id),
                    index: i,
                    step: step,
                    running: playing && widget.player.stepIndex == i,
                    onEdit: () => _edit(sequence, step),
                    onGoTo: () => widget.arm.setPose(step.angles),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(ArmSequence sequence, ArmStep step) async {
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
                  decoration: const InputDecoration(border: OutlineInputBorder()),
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
                          _use(widget.store.removeStep(sequence, step.id));
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
                            sequence,
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
class _Sequences extends StatelessWidget {
  const _Sequences({
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
        for (final sequence in store.sequences)
          GestureDetector(
            onTap: () => onPick(sequence),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: sequence.id == current.id
                    ? accent.withValues(alpha: 0.2)
                    : context.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sequence.id == current.id
                      ? accent
                      : context.glassStroke,
                ),
              ),
              child: Text(
                '${sequence.name} · ${sequence.steps.length}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: () => onPick(store.add(name: 'Routine ${store.sequences.length + 1}')),
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
    required this.sequence,
    required this.player,
    required this.onRecord,
    required this.onChanged,
  });

  final ArmSequence sequence;
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
                  onPressed: sequence.steps.isEmpty
                      ? null
                      : () => playing ? player.stop() : player.play(sequence),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Dial(
            label: 'Wait between steps',
            value: '${(sequence.gap.inMilliseconds / 1000).toStringAsFixed(1)} s',
            slider: ServoSlider(
              value: sequence.gap.inMilliseconds.toDouble(),
              min: 0,
              max: 5000,
              onChanged: (v) => onChanged(
                sequence.copyWith(gap: Duration(milliseconds: v.round())),
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
                value: sequence.loop,
                onChanged: (v) => onChanged(sequence.copyWith(loop: v)),
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
              icon: Icon(Icons.my_location, size: 18, color: context.glassMuted),
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
