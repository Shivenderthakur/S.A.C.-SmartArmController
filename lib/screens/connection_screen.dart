import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/arm_controller.dart';
import '../services/arm_link.dart';
import '../widgets/glass.dart';
import '../widgets/glass_segmented.dart';
import '../widgets/screen_body.dart';
import '../widgets/servo_slider.dart';

/// Where the arm lives on the network, and whether to talk to it.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.settings,
    required this.link,
    required this.arm,
    this.trailing,
  });

  final AppSettings settings;
  final ArmLink link;
  final ArmController arm;
  final Widget? trailing;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final _host = TextEditingController(text: widget.settings.host);
  String? _pingResult;
  bool _pinging = false;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    widget.settings.host = _host.text;
    setState(() {
      _pinging = true;
      _pingResult = null;
    });
    final result = await widget.link.ping();
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _pingResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = widget.settings;

    return ListenableBuilder(
      listenable: Listenable.merge([settings, widget.link, widget.arm]),
      builder: (context, _) => ScreenBody(
        kicker: 'Link',
        title: 'The arm',
        trailing: widget.trailing,
        children: [
          GlassCard(
            child: Row(
              children: [
                Icon(_stateIcon, color: _stateColour(scheme), size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.link.message,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.link.sent} sent · ${widget.link.failed} failed'
                        '${settings.transport == ArmTransport.tcp ? ' · ${widget.link.reconnects} reconnects' : ''}',
                        style: monoStyle(size: 12, colour: context.glassMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const GlassLabel('ESP32 address'),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            radius: 18,
            child: TextField(
              controller: _host,
              style: monoStyle(size: 15, colour: scheme.onSurface),
              decoration: InputDecoration(
                hintText: '192.168.1.50',
                hintStyle: monoStyle(size: 15, colour: context.glassMuted),
                prefixIcon: Icon(Icons.router_outlined, color: context.glassMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (v) => settings.host = v,
              onChanged: (v) => settings.host = v,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Host or IP on the same WiFi. Port optional.',
            style: TextStyle(fontSize: 12, color: context.glassMuted),
          ),
          const SizedBox(height: 22),
          const GlassLabel('Transport'),
          GlassSegmented<ArmTransport>(
            value: settings.transport,
            onChanged: (v) => settings.transport = v,
            segments: const [
              Segment(ArmTransport.http, Icons.public, 'HTTP'),
              Segment(ArmTransport.tcp, Icons.bolt, 'Socket'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            settings.transport == ArmTransport.tcp
                ? 'One connection, held open, on port '
                    '${widget.link.hostPort().$2}. No handshake and no headers '
                    'per command, so an angle lands in a millisecond or two '
                    'rather than twenty or forty. The catch is that a write '
                    'into a socket whose peer has gone still succeeds — so the '
                    'arm answers every command, and silence for three seconds '
                    'is taken as a dead link and the socket is rebuilt.'
                : 'A connection per command, which is slower, but every command '
                    'carries its own timeout — a failure is immediate and '
                    'unmistakable. Reflash the sketch in esp32/ before '
                    'switching to the socket.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.glassMuted,
            ),
          ),
          const SizedBox(height: 14),
          GlassButton(
            label: _pinging ? 'Testing…' : 'Test connection',
            icon: Icons.wifi_tethering,
            onPressed: _pinging ? null : _test,
          ),
          if (_pingResult != null) ...[
            const SizedBox(height: 12),
            GlassWell(
              child: Text(
                _pingResult!,
                style: monoStyle(size: 12).copyWith(height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Row(
              children: [
                Icon(Icons.send_outlined, size: 22, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send angles to the arm',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Off by default, so the arm cannot move until you say '
                        'so.',
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
                  value: settings.streaming,
                  onChanged: (v) => settings.streaming = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const GlassLabel('Rate limit'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'At most one command every',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.glassMuted,
                        ),
                      ),
                    ),
                    Text(
                      '${settings.sendIntervalMs} ms',
                      style: monoStyle(size: 24, colour: scheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ServoSlider(
                  value: settings.sendIntervalMs.toDouble(),
                  min: 40,
                  max: 400,
                  onChanged: (v) => settings.sendIntervalMs = v.round(),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tracking runs near 25 fps. A small HTTP server and a servo '
                  'cannot take that, so commands are throttled and coalesced — '
                  'only the newest position is ever sent. That is '
                  '${(1000 / settings.sendIntervalMs).toStringAsFixed(1)} per '
                  'second.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.glassMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _stateIcon => switch (widget.link.state) {
        LinkState.ok => Icons.check_circle_outline,
        LinkState.error => Icons.error_outline,
        LinkState.sending => Icons.sync,
        LinkState.idle => Icons.radio_button_unchecked,
      };

  Color _stateColour(ColorScheme scheme) => switch (widget.link.state) {
        LinkState.ok => const Color(0xFF34D399),
        LinkState.error => scheme.error,
        _ => context.glassMuted,
      };
}
