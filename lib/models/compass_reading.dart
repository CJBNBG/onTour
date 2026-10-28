/// Eine einzelne Kompass-Messung, wie sie vom [CompassService] geliefert
/// wird.
class CompassReading {
  /// Peilung in Grad (0-360), gemessen gegen Norden, im Uhrzeigersinn.
  final double headingDegrees;

  /// Genauigkeit der Peilung in Grad, sofern von der Plattform geliefert.
  /// null, wenn keine Angabe vorliegt.
  final double? accuracyDegrees;

  /// NEU (README Abschnitt 46): true, solange das Magnetfeld unplausibel
  /// ist (zu schwach/stark oder stark abweichend) - die Peilung läuft
  /// dann nur auf dem Gyroskop weiter (siehe CompassService).
  final bool isDisturbed;

  /// NEU (README Abschnitt 46): Geglättete Magnetfeldstärke in µT, null
  /// ohne Magnetometer-Wert.
  final double? fieldStrengthMicroTesla;

  CompassReading({
    required this.headingDegrees,
    required this.accuracyDegrees,
    this.isDisturbed = false,
    this.fieldStrengthMicroTesla,
  });
}
