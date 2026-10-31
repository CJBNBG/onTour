import 'package:flutter/material.dart';

/// Einheitlicher Textstil für alle "Genauigkeit: ..."-Zeilen der App
/// (Tacho-, Kompass-Seite): bewusst klein, aber noch gut lesbar. Eine
/// einzige Stelle statt je Seite eigener Berechnung, damit die Größe
/// überall identisch bleibt. Die Größe skaliert weiterhin mit der
/// Schriftgröße des Systems.
const double kAccuracyFontSize = 15;

TextStyle? accuracyTextStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.bodyMedium;
  return base?.copyWith(fontSize: kAccuracyFontSize);
}
