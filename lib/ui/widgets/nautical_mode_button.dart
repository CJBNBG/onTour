import 'package:flutter/material.dart';

/// Runder Kartenüberlagerungs-Button zum Umschalten zwischen Landkarte und
/// Seekarte (Seemarken-Overlay von OpenSeaMap, siehe README Abschnitt 9
/// für die genaue Bedeutung von "Seekarte" in dieser App).
///
/// Rein darstellend/steuernd - das eigentliche Persistieren der Wahl über
/// [AppPreferences] obliegt der aufrufenden Seite (siehe [onChanged]),
/// damit dieses Widget unabhängig von der konkreten Preferences-Klasse
/// bleibt und z. B. auch in der Track-Detailansicht ohne Persistierung
/// verwendet werden könnte.
class NauticalModeButton extends StatelessWidget {
  final bool nauticalMode;
  final ValueChanged<bool> onChanged;

  const NauticalModeButton({
    super.key,
    required this.nauticalMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: nauticalMode ? 'Zur Landkarte wechseln' : 'Zur Seekarte wechseln (Seemarken-Overlay)',
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChanged(!nauticalMode),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              nauticalMode ? Icons.sailing : Icons.map,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
