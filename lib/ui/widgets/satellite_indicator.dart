import 'package:flutter/material.dart';

import '../../services/device_status_service.dart';

/// Anzahl der Satelliten im Fix als kleines Symbol mit Zahl - sitzt in der
/// AppBar links neben dem Info-Button und ist dadurch auf jeder Seite
/// sichtbar (siehe README Abschnitt 62). Farbe nach Empfangsqualität:
/// grau = keine aktuellen Daten, rot = 0, orange = 1-3, grün = ab 4.
///
/// Hört selbst auf den [DeviceStatusService] (aus HomeShell), baut also
/// nur dieses kleine Widget neu, wenn sich die Satellitenzahl ändert.
class SatelliteIndicator extends StatelessWidget {
  final DeviceStatusService status;

  const SatelliteIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final count = status.satelliteCount;
        final fresh = status.satellitesFresh && count != null;
        final Color color;
        if (!fresh) {
          color = Colors.grey;
        } else if (count == 0) {
          color = Colors.red;
        } else if (count < 4) {
          color = Colors.orange;
        } else {
          color = Colors.green;
        }

        return Tooltip(
          message: fresh ? 'Satelliten im Fix: $count' : 'Keine aktuellen Satellitendaten',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.satellite_alt, size: 20, color: color),
                const SizedBox(width: 4),
                Text(
                  fresh ? '$count' : '–',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
