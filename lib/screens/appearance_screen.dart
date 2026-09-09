import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../widgets/glass.dart';
import '../widgets/glass_segmented.dart';
import '../widgets/screen_body.dart';

/// Theme changes apply as you make them — the whole app rebuilds off the same
/// settings object, so there is nothing to confirm and nothing to restart.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.settings, this.trailing});

  final AppSettings settings;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ScreenBody(
        kicker: 'Appearance',
        title: 'Look and feel',
        trailing: trailing,
        children: [
          const GlassLabel('Theme'),
          // Tap a segment or drag the pill between them — the same control the
          // nav bar is, at a smaller size.
          GlassSegmented<ThemeMode>(
            value: settings.themeMode,
            onChanged: (v) => settings.themeMode = v,
            segments: const [
              Segment(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
              Segment(ThemeMode.system, Icons.brightness_auto_outlined, 'Auto'),
              Segment(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Auto follows the phone, and switches the moment it does.',
            style: TextStyle(fontSize: 12, color: context.glassMuted),
          ),
          const SizedBox(height: 24),
          const GlassLabel('Accent'),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < AppSettings.accents.length; i++)
                      _Swatch(
                        label: AppSettings.accents[i].$1,
                        colour: AppSettings.accents[i].$2,
                        selected: settings.accent == i,
                        onTap: () => settings.accent = i,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Also the colour of the hand skeleton over the camera, and '
                  'of the pill under the nav bar.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.glassMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Row(
              children: [
                Icon(
                  Icons.flip,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mirror the overlay',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Whether the platform mirrors the front camera varies '
                        'by device. If the skeleton lands on the mirror image '
                        'of your hand, turn this around. It never changes the '
                        'angles.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: context.glassMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.mirrorOverlay,
                  onChanged: (v) => settings.mirrorOverlay = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AboutTile(),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: selected ? 52 : 44,
              height: selected ? 52 : 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(colour, Colors.white, 0.35)!,
                    colour,
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: selected ? 16 : 8,
                    offset: const Offset(0, 5),
                    color: colour.withValues(alpha: selected ? 0.55 : 0.25),
                  ),
                ],
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 22)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : context.glassMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AboutTile extends StatelessWidget {
  const AboutTile({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart Arm Controller',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'On-device MediaPipe hand tracking, driving four servos over the '
            'local network. Nothing leaves your WiFi.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: context.glassMuted,
            ),
          ),
        ],
      ),
    );
  }
}
