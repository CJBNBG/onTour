import 'package:flutter/material.dart';

import '../../services/device_status_service.dart';

/// Schmaler Statusbereich unter der App-Leiste, auf allen Seiten sichtbar:
/// links die Zahl der Satelliten im Fix (Farbe nach Empfangsqualität),
/// rechts ein farbiges Symbol für Stillstand/Bewegung.
///
/// Satelliten: grau = keine aktuellen Daten, rot = 0, orange = 1-3,
/// grün = ab 4. Stillstand: orange = Stillstand erkannt, grün = in
/// Bewegung, grau = unbekannt.
class AppStatusBar extends StatelessWidget {
  final DeviceStatusService status;

  const AppStatusBar({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final count = status.satelliteCount;
        final fresh = status.satellitesFresh && count != null;
        final satColor = !fresh
            ? Colors.grey
            : count == 0
                ? Colors.red
                : count < 4
                    ? Colors.orange
                    : Colors.green;

        final stationary = status.displayStationary;
        final IconData motionIcon = stationary == null
            ? Icons.remove_circle_outline
            : stationary
                ? Icons.pause_circle
                : Icons.play_circle;
        final motionColor = stationary == null
            ? Colors.grey
            : stationary
                ? Colors.orange
                : Colors.green;

        return Material(
          color: scheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Tooltip(
                  message: fresh
                      ? 'Satelliten im Fix: $count'
                      : 'Keine aktuellen Satellitendaten',
                  child: Row(
                    children: [
                      Icon(Icons.satellite_alt, size: 20, color: satColor),
                      const SizedBox(width: 6),
                      Text(
                        fresh ? '$count' : '–',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: satColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: stationary == null
                      ? 'Bewegungszustand unbekannt'
                      : stationary
                          ? 'Stillstand erkannt'
                          : 'In Bewegung',
                  child: Icon(motionIcon, size: 22, color: motionColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
