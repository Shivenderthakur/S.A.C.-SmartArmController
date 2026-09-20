import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/board.dart';
import '../models/joint.dart';
import '../services/arm_link.dart';
import '../services/joint_config.dart';
import '../widgets/glass.dart';
import '../widgets/screen_body.dart';

/// One servo: the joint it belongs to, and whether it is that joint's second,
/// opposed one. A claw is two of these.
typedef ServoRef = ({int channel, bool mirror});

/// Wire the arm: drag a servo onto the pin it is plugged into.
///
/// The board keeps no map of its own, so whatever is set here is pushed down
/// the link on every connect.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.config,
    required this.link,
    this.trailing,
    this.layout,
  });

  final JointConfig config;
  final ArmLink link;
  final Widget? trailing;

  /// An already-parsed board, for tests: reading the asset is real I/O, which a
  /// widget test only runs inside `runAsync`.
  final BoardLayout? layout;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final Future<BoardLayout> _layout =
      widget.layout == null ? BoardLayout.load() : Future.value(widget.layout);

  /// The servo waiting for a pin, for people who would rather tap twice than
  /// drag.
  ServoRef? _armed;

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );

  void _assign(ServoRef servo, int gpio) {
    final result =
        widget.config.assign(servo.channel, gpio, mirror: servo.mirror);
    setState(() => _armed = null);

    if (result == AssignResult.ok) {
      HapticFeedback.selectionClick();
      widget.link.pushMap();
      return;
    }

    final owner = widget.config.ownerOf(gpio);
    _say(result == AssignResult.taken && owner != null
        ? 'GPIO$gpio already drives ${widget.config.joints[owner].name}'
        : 'GPIO$gpio cannot drive a servo');
  }

  void _clear(ServoRef servo) {
    widget.config.unassign(servo.channel, mirror: servo.mirror);
    widget.link.pushMap();
  }

  /// Give a joint a second servo, or take it away. The new one lands on the
  /// first free pin so it is wired rather than merely declared.
  void _setTwoServos(int channel, bool on) {
    widget.config.setTwoServos(channel, on);

    // Wire it straight away if there is a spare pin; otherwise it waits in the
    // list to be dragged onto one, like any other unwired servo.
    if (on) {
      final free = allowedPins.firstWhere(
        (p) => widget.config.ownerOf(p) == null,
        orElse: () => Joint.unassigned,
      );
      if (free != Joint.unassigned) {
        widget.config.assign(channel, free, mirror: true);
      }
    }
    widget.link.pushMap();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.config, widget.link]),
      builder: (context, _) {
        final config = widget.config;

        return ScreenBody(
          kicker: 'Hardware',
          title: 'Board and pins',
          trailing: widget.trailing,
          children: [
            _JointCount(config: config, onChanged: widget.link.pushMap),
            const SizedBox(height: 10),
            _DofPresets(config: config, onChanged: widget.link.pushMap),
            const SizedBox(height: 14),
            _TwoServoJoints(config: config, onChanged: _setTwoServos),
            const SizedBox(height: 14),
            const GlassLabel('Drag a servo onto the pin it is wired to'),
            _Unassigned(
              config: config,
              armed: _armed,
              onArm: (servo) => setState(
                () => _armed = _armed == servo ? null : servo,
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<BoardLayout>(
              future: _layout,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return GlassWell(
                    child: Text(
                      'The board drawing could not be read. Pins can still be '
                      'assigned from the Control screen.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.glassMuted,
                      ),
                    ),
                  );
                }
                final layout = snapshot.data;
                if (layout == null) {
                  return const SizedBox(
                    height: 320,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _Board(
                  layout: layout,
                  config: config,
                  armed: _armed,
                  onDrop: _assign,
                  onClear: _clear,
                );
              },
            ),
            const SizedBox(height: 16),
            _Status(config: config, link: widget.link),
          ],
        );
      },
    );
  }
}

/// How many joints the arm has. Eight plus a gripper is the ceiling, because
/// that is how many pins can carry a servo.
class _JointCount extends StatelessWidget {
  const _JointCount({required this.config, required this.onChanged});

  final JointConfig config;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    void resize(int to) {
      config.resize(to);
      onChanged();
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Joints',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${config.servos} servos. ${config.trackingUsable ? "The camera can drive this arm" : "Too many joints for the camera — sliders and steps only"}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: context.glassMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                config.channels > 1 ? () => resize(config.channels - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${config.channels}', style: monoStyle(size: 22, colour: accent)),
          IconButton(
            onPressed: config.channels < maxJoints
                ? () => resize(config.channels + 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

/// The arm shapes worth one tap, so nobody holds the stepper down to nine.
class _DofPresets extends StatelessWidget {
  const _DofPresets({required this.config, required this.onChanged});

  static const _presets = [4, 5, 6, 8, 9];

  final JointConfig config;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final count in _presets)
          GestureDetector(
            onTap: () {
              config.resize(count);
              onChanged();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: config.channels == count
                    ? accent.withValues(alpha: 0.2)
                    : context.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      config.channels == count ? accent : context.glassStroke,
                ),
              ),
              child: Text(
                '$count DOF',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: config.channels == count ? null : context.glassMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Which joints close with two servos facing each other.
class _TwoServoJoints extends StatelessWidget {
  const _TwoServoJoints({required this.config, required this.onChanged});

  final JointConfig config;
  final void Function(int channel, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Two servos',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'A claw closes with a pair facing each other. The second one '
            'follows the first at the opposite angle — one slider, two servos.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: context.glassMuted,
            ),
          ),
          for (var i = 0; i < config.channels; i++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    config.joints[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                Switch(
                  value: config.joints[i].twoServos,
                  onChanged: (v) => onChanged(i, v),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The servos with nowhere to go yet.
class _Unassigned extends StatelessWidget {
  const _Unassigned({
    required this.config,
    required this.armed,
    required this.onArm,
  });

  final JointConfig config;
  final ServoRef? armed;
  final ValueChanged<ServoRef> onArm;

  @override
  Widget build(BuildContext context) {
    final loose = <ServoRef>[
      for (var i = 0; i < config.channels; i++)
        if (!config.joints[i].assigned) (channel: i, mirror: false),
      for (var i = 0; i < config.channels; i++)
        if (config.joints[i].twoServos && !config.joints[i].mirrorAssigned)
          (channel: i, mirror: true),
    ];

    if (loose.isEmpty) {
      return Text(
        'Every servo has a pin.',
        style: TextStyle(fontSize: 12, color: context.glassMuted),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final servo in loose)
          _ServoChip(
            servo: servo,
            label: config.joints[servo.channel].name,
            armed: armed == servo,
            onTap: () => onArm(servo),
          ),
      ],
    );
  }
}

class _ServoChip extends StatelessWidget {
  const _ServoChip({
    required this.servo,
    required this.label,
    required this.armed,
    this.onTap,
  });

  final ServoRef servo;
  final String label;
  final bool armed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: armed ? accent.withValues(alpha: 0.22) : context.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: armed ? accent : context.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${servo.channel + 1}${servo.mirror ? "b" : ""}',
            style: monoStyle(size: 12, colour: accent),
          ),
          const SizedBox(width: 8),
          Text(
            servo.mirror ? '$label, 2nd' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Draggable<ServoRef>(
        data: servo,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.9, child: chip),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: chip),
        child: chip,
      ),
    );
  }
}

/// The board drawing, with a rail of pin blocks down each side.
///
/// The pins themselves are 2.54 mm apart, which is about nine logical pixels at
/// this size — far too small to drop onto. So the blocks are spread evenly down
/// the rail and a leader line joins each one to its real place on the board.
class _Board extends StatelessWidget {
  const _Board({
    required this.layout,
    required this.config,
    required this.armed,
    required this.onDrop,
    required this.onClear,
  });

  final BoardLayout layout;
  final JointConfig config;
  final ServoRef? armed;
  final void Function(ServoRef servo, int gpio) onDrop;
  final ValueChanged<ServoRef> onClear;

  static const _railWidth = 96.0;
  static const _blockHeight = 38.0;

  @override
  Widget build(BuildContext context) {
    final pins = [
      for (final gpio in allowedPins)
        if (layout.forGpio(gpio) != null) layout.forGpio(gpio)!,
    ];
    final left = pins.where((p) => p.onLeftHeader).toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    final right = pins.where((p) => !p.onLeftHeader).toList()
      ..sort((a, b) => a.y.compareTo(b.y));

    return LayoutBuilder(
      builder: (context, constraints) {
        final boardWidth =
            (constraints.maxWidth - _railWidth * 2 - 16).clamp(70.0, 150.0);
        final boardHeight =
            boardWidth * BoardLayout.heightMm / BoardLayout.widthMm;
        final height = boardHeight.clamp(260.0, 460.0);
        final boardLeft = (constraints.maxWidth - boardWidth) / 2;

        double blockCentre(int index, int count) =>
            (index + 0.5) / count * height;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LeaderLines(
                    left: [
                      for (var i = 0; i < left.length; i++)
                        (
                          blockCentre(i, left.length),
                          left[i].y / BoardLayout.heightMm * height,
                        ),
                    ],
                    right: [
                      for (var i = 0; i < right.length; i++)
                        (
                          blockCentre(i, right.length),
                          right[i].y / BoardLayout.heightMm * height,
                        ),
                    ],
                    boardLeft: boardLeft,
                    boardRight: boardLeft + boardWidth,
                    railWidth: _railWidth,
                    colour: context.glassMuted,
                  ),
                ),
              ),
              Positioned(
                left: boardLeft,
                width: boardWidth,
                height: height,
                child: SvgPicture.asset(
                  BoardLayout.svgAsset,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                ),
              ),
              for (var i = 0; i < left.length; i++)
                Positioned(
                  left: 0,
                  width: _railWidth,
                  top: blockCentre(i, left.length) - _blockHeight / 2,
                  height: _blockHeight,
                  child: _PinBlock(
                    pin: left[i],
                    config: config,
                    armed: armed,
                    onDrop: onDrop,
                    onClear: onClear,
                  ),
                ),
              for (var i = 0; i < right.length; i++)
                Positioned(
                  right: 0,
                  width: _railWidth,
                  top: blockCentre(i, right.length) - _blockHeight / 2,
                  height: _blockHeight,
                  child: _PinBlock(
                    pin: right[i],
                    config: config,
                    armed: armed,
                    onDrop: onDrop,
                    onClear: onClear,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LeaderLines extends CustomPainter {
  const _LeaderLines({
    required this.left,
    required this.right,
    required this.boardLeft,
    required this.boardRight,
    required this.railWidth,
    required this.colour,
  });

  /// (block centre, pin position) pairs, both vertical offsets.
  final List<(double, double)> left;
  final List<(double, double)> right;
  final double boardLeft;
  final double boardRight;
  final double railWidth;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final (block, pin) in left) {
      final path = Path()
        ..moveTo(railWidth, block)
        ..lineTo((railWidth + boardLeft) / 2, block)
        ..lineTo(boardLeft, pin);
      canvas.drawPath(path, paint);
      canvas.drawCircle(Offset(boardLeft, pin), 2.5, Paint()..color = colour);
    }

    for (final (block, pin) in right) {
      final path = Path()
        ..moveTo(size.width - railWidth, block)
        ..lineTo((size.width - railWidth + boardRight) / 2, block)
        ..lineTo(boardRight, pin);
      canvas.drawPath(path, paint);
      canvas.drawCircle(Offset(boardRight, pin), 2.5, Paint()..color = colour);
    }
  }

  @override
  bool shouldRepaint(_LeaderLines old) =>
      old.left != left || old.right != right || old.colour != colour;
}

/// One pin: a drop target, and the servo that landed on it.
class _PinBlock extends StatelessWidget {
  const _PinBlock({
    required this.pin,
    required this.config,
    required this.armed,
    required this.onDrop,
    required this.onClear,
  });

  final BoardPin pin;
  final JointConfig config;
  final ServoRef? armed;
  final void Function(ServoRef servo, int gpio) onDrop;
  final ValueChanged<ServoRef> onClear;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final owner = config.ownerOf(pin.gpio);
    final mirror = config.isMirrorPin(pin.gpio);
    final taken = owner != null;
    final here = taken ? (channel: owner, mirror: mirror) : null;

    return DragTarget<ServoRef>(
      onWillAcceptWithDetails: (details) => here == null || here == details.data,
      onAcceptWithDetails: (details) => onDrop(details.data, pin.gpio),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty || (armed != null && !taken);

        return GestureDetector(
          onTap: () {
            if (armed != null) {
              onDrop(armed!, pin.gpio);
            } else if (here != null) {
              onClear(here);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: taken
                  ? accent.withValues(alpha: 0.18)
                  : hot
                      ? accent.withValues(alpha: 0.1)
                      : context.glassFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: taken || hot ? accent : context.glassStroke,
                width: hot ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'GP${pin.label}',
                  style: monoStyle(size: 11, colour: context.glassMuted),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    !taken
                        ? 'free'
                        : mirror
                            ? '${config.joints[owner].name}, 2nd'
                            : config.joints[owner].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: taken ? null : context.glassMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What the board says it did with the map.
class _Status extends StatelessWidget {
  const _Status({required this.config, required this.link});

  final JointConfig config;
  final ArmLink link;

  @override
  Widget build(BuildContext context) {
    final mask = link.attachedMask;
    final wired =
        config.pinMap.where((p) => p != Joint.unassigned).length;

    final String state;
    if (!link.connected) {
      state = 'Not connected — the map is pushed the moment the arm answers.';
    } else if (mask == null) {
      state = 'Connected. Waiting for the board to confirm the map.';
    } else {
      final attached = List.generate(config.pinMap.length, (i) => i)
          .where((i) => mask & (1 << i) != 0)
          .length;
      state = attached == wired
          ? 'The board attached all $attached servos.'
          : 'The board attached $attached of $wired servos.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlassLabel('On the board'),
        GlassWell(
          child: Text(
            state,
            style:
                TextStyle(fontSize: 12, height: 1.4, color: context.glassMuted),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Servos draw far more current than the board can supply: power them '
          'separately and tie the grounds together. GPIO16 and GPIO17 are wired '
          'to the memory on WROVER modules and cannot drive a servo there.',
          style:
              TextStyle(fontSize: 12, height: 1.4, color: context.glassMuted),
        ),
      ],
    );
  }
}
