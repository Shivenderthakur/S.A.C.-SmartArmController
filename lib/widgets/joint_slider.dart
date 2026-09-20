import 'package:flutter/material.dart';

import '../services/arm_controller.dart';
import 'glass.dart';
import 'servo_slider.dart';

/// One joint: its name, its travel, and a slider that drives the servo now.
///
/// Shared by the Control screen and the Add step sheet, so posing the arm is
/// the same gesture in both. It listens to the arm itself rather than letting
/// the screen do it — an angle moving twelve times a second should repaint one
/// card, not a whole page of them.
class JointSlider extends StatelessWidget {
  const JointSlider({super.key, required this.arm, required this.index});

  final ArmController arm;
  final int index;

  @override
  Widget build(BuildContext context) {
    final joint = arm.config.joints[index];
    final accent = Theme.of(context).colorScheme.primary;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
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
                    Row(
                      children: [
                        if (joint.isGripper) ...[
                          Icon(
                            Icons.pan_tool_alt_outlined,
                            size: 15,
                            color: context.glassMuted,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            joint.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      joint.twoServos
                          ? '${joint.min}–${joint.max}°, two servos'
                          : '${joint.min}–${joint.max}°',
                      style: TextStyle(fontSize: 11.5, color: context.glassMuted),
                    ),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: arm,
                builder: (context, _) => Text(
                  '${arm.angles[index]}',
                  style: monoStyle(size: 24, colour: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
