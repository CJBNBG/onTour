import 'package:flutter/material.dart';

import '../../models/speed_accuracy_mode.dart';

/// Kleines, farbiges Badge, das die auf der jeweiligen Seite AKTUELL
/// verwendete Genauigkeitsstufe anzeigt (siehe README Abschnitt 37) -
/// auf der Tacho-Seite die vom Nutzer gewählte Einstellung (Abschnitt
/// 4), auf Kompass- und Track-Seite die dort jeweils fest
/// einprogrammierte Stufe (siehe [SpeedAccuracyMode.fromLocationAccuracy]).
///
/// Bewusst rein informativ/nicht antippbar - eine Änderung ist
/// weiterhin ausschließlich über die Einstellungsseite möglich (und
/// wirkt sich ohnehin nur auf die Tacho-Seite aus).
class AccuracyBadge extends StatelessWidget {
  final SpeedAccuracyMode mode;

  const AccuracyBadge({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: mode.description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: mode.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: mode.color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_fixed, size: 14, color: mode.color),
            const SizedBox(width: 6),
            // Bewusst normales Text-Widget statt AutoHyphenatingText -
            // analog zur bereits mehrfach im Projekt dokumentierten
            // Einschränkung bei kurzen, einzeiligen Labels in beengten
            // Layouts (siehe README Abschnitt 13/24/26).
            Text(
              mode.label,
              style: TextStyle(
                color: mode.color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
