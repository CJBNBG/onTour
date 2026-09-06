/// Eine einzelne Höhen-Messung, wie sie vom [AltitudeService] geliefert
/// wird.
///
/// WICHTIG (Genauigkeits-Hinweis): GPS-Höhenwerte sind grundsätzlich
/// deutlich ungenauer als die horizontale Position - selbst bei gutem
/// Empfang sind Abweichungen von 10-30 m keine Seltenheit, da die
/// Satellitengeometrie für die Höhenbestimmung ungünstiger ist als für
/// die waagerechte Position. Die mitgelieferte Genauigkeit
/// ([altitudeAccuracyMeters]) macht das transparent - deshalb wird sie in
/// der UI immer direkt neben dem Wert angezeigt, nicht separat versteckt.
class AltitudeReading {
  /// Höhe in Metern (i. d. R. bereits auf Meereshöhe bezogen, sofern das
  /// Betriebssystem das entsprechend aufbereitet - siehe Hinweis oben).
  final double altitudeMeters;

  /// Genauigkeit der Höhenangabe in Metern, sofern von der Plattform
  /// geliefert. null, wenn keine Angabe vorliegt.
  final double? altitudeAccuracyMeters;

  final DateTime timestamp;

  AltitudeReading({
    required this.altitudeMeters,
    required this.altitudeAccuracyMeters,
    required this.timestamp,
  });
}
