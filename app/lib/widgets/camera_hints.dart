import 'package:flutter/material.dart';

/// Max orientation spread (degrees) over the last 0.6 s that still counts as "steady".
const maxShakeDeg = 1.5;

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.action, this.onTap});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: Icon(icon),
      content: Text(text),
      actions: [
        if (action != null)
          TextButton(onPressed: onTap, child: Text(action!))
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class CaptureTips extends StatelessWidget {
  const CaptureTips({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: Text(
              'For best results:\n'
              '• Hold the phone steady (rest it on something if you can)\n'
              '• Turn on Night mode if your camera has it\n'
              '• Avoid city lights, the Moon and buildings in the frame',
              style: TextStyle(height: 1.4),
            ),
          ),
          IconButton(
              tooltip: 'Hide tips', icon: const Icon(Icons.close, size: 18), onPressed: onClose),
        ]),
      ),
    );
  }
}

class SteadyIndicator extends StatelessWidget {
  const SteadyIndicator({super.key, required this.shakeDeg});

  final double shakeDeg;

  @override
  Widget build(BuildContext context) {
    final steady = shakeDeg <= maxShakeDeg;
    return Center(
      child: Chip(
        avatar: Icon(steady ? Icons.check_circle : Icons.pan_tool_alt_outlined,
            color: steady ? Colors.greenAccent : Colors.amber, size: 18),
        label: Text(steady ? 'Steady' : 'Hold steady…'),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
      ),
    );
  }
}
