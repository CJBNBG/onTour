/// Eine einzelne Kompass-Messung, wie sie vom [CompassService] geliefert
/// wird.
class CompassReading {
  /// Peilung in Grad (0-360), gemessen gegen Norden, im Uhrzeigersinn.
  final double headingDegrees;

  /// Genauigkeit der Peilung in Grad, sofern von der Plattform geliefert.
  /// null, wenn keine Angabe vorliegt.
  final double? accuracyDegrees;

  CompassReading({required this.headingDegrees, required this.accuracyDegrees});
}
