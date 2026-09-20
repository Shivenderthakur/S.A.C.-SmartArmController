import 'package:flutter/material.dart';

import '../services/arm_controller.dart';
import '../widgets/glass.dart';
import '../widgets/joint_slider.dart';
import '../widgets/screen_body.dart';

/// Drive the arm by hand, one slider per joint.
///
/// Touching a slider switches the arm to manual, because otherwise the next
/// tracked frame would overwrite whatever was just set. Recording these poses
/// into a routine is the Steps screen.
class ControlScreen extends StatelessWidget {
  const ControlScreen({super.key, required this.arm, this.trailing});

  final ArmController arm;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: arm.config,
      builder: (context, _) => ScreenBody(
        kicker: 'Manual',
        title: 'Custom control',
        trailing: trailing,
        children: [
          _Mode(arm: arm),
          const SizedBox(height: 12),
          for (var i = 0; i < arm.config.channels; i++) ...[
            JointSlider(arm: arm, index: i),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Centre all',
                  icon: Icons.center_focus_strong_outlined,
                  onPressed: arm.centre,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: arm,
                  builder: (context, _) => GlassButton(
                    label: 'Back to hand',
                    icon: Icons.videocam_outlined,
                    onPressed: arm.config.trackingUsable && arm.manual
                        ? () => arm.manual = false
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
        final ai = tracked && !arm.manual;
        final accent = Theme.of(context).colorScheme.primary;

        return GlassCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            children: [
              Icon(
                ai ? Icons.auto_awesome : Icons.pan_tool,
                size: 22,
                color: accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          ai ? 'AI mode' : 'Manual control',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (ai) ...[
                          const SizedBox(width: 8),
                          _OnBadge(colour: accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !tracked
                          ? 'This arm has more joints than the camera can '
                              'drive, so the sliders are how it moves.'
                          : ai
                              ? 'Your hand is driving the arm. Move a slider to '
                                  'take over.'
                              : 'The sliders drive the arm. Tracking still runs '
                                  'but is ignored.',
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
                Switch(value: arm.manual, onChanged: (v) => arm.manual = v),
            ],
          ),
        );
      },
    );
  }
}

/// The little "on" tag beside AI mode, so it is never a guess.
class _OnBadge extends StatelessWidget {
  const _OnBadge({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colour.withValues(alpha: 0.4)),
        ),
        child: Text(
          'ON',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: colour,
          ),
        ),
      );
}
