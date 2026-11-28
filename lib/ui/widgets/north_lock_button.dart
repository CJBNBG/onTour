import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Steuerelement zum Ausrichten der Karte nach Norden UND zum Einrasten
/// dieser Ausrichtung - Standard-Verhalten aus der frühen, inzwischen
/// entfallenen eigenständigen Kartenseite (siehe README Abschnitt 9), auf
/// vielfachen Wunsch wieder in die Kartenansichten integriert. Der Pfeil
/// dreht sich passend zur aktuellen Kartendrehung mit (zeigt also stets
/// die tatsächliche Richtung "Norden" auf dem Bildschirm an). Ein
/// Antippen schaltet zwischen zwei Zuständen um:
/// - Nicht eingerastet -> Antippen setzt die Kartendrehung einmalig auf
///   0° zurück UND rastet die Nordausrichtung anschließend ein (Dreh-
///   Geste wird deaktiviert) - kein zweiter Tap nötig.
/// - Eingerastet -> Antippen gibt die Dreh-Geste wieder frei.
///
/// Rein darstellend - das eigentliche Drehen der Karte sowie das
/// Aktivieren/Deaktivieren der Dreh-Geste (über `InteractionOptions` in
/// den jeweiligen `MapOptions`) obliegt der aufrufenden Seite, siehe
/// [onToggle]. Den Anfangszustand legt die aufrufende Seite fest
/// (Karten-Tab: eingerastet, Track-Detailansicht: frei drehbar) - er wird
/// bewusst nicht persistiert, siehe README Abschnitt 5.
class NorthLockButton extends StatelessWidget {
  final double rotationDegrees;
  final bool locked;
  final VoidCallback onToggle;

  const NorthLockButton({
    super.key,
    required this.rotationDegrees,
    required this.locked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: locked ? 'Nordausrichtung wieder freigeben' : 'Nordausrichtung einrasten',
      child: Material(
        color: locked ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Transform.rotate(
                  angle: -rotationDegrees * math.pi / 180,
                  child: Icon(
                    Icons.navigation,
                    color: locked ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (locked)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Icon(
                      Icons.lock,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
