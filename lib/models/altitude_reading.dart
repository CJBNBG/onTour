/// Eine einzelne Positions-/Höhen-Messung, wie sie vom [AltitudeService]
/// geliefert wird.
///
/// WICHTIG (Genauigkeits-Hinweis): GPS-Höhenwerte sind grundsätzlich
/// deutlich ungenauer als die horizontale Position - selbst bei gutem
/// Empfang sind Abweichungen von 10-30 m keine Seltenheit, da die
/// Satellitengeometrie für die Höhenbestimmung ungünstiger ist als für
/// die waagerechte Position. Die mitgelieferte Genauigkeit
/// ([altitudeAccuracyMeters]) macht das transparent - deshalb wird sie in
/// der UI immer direkt neben dem Wert angezeigt, nicht separat versteckt.
///
/// NEU (Position): Enthält seit der DMS-Positionsanzeige auf der
/// Kompass-Seite zusätzlich [latitude]/[longitude] - beide stammen aus
/// demselben zugrunde liegenden GPS-Positions-Stream wie die Höhe (siehe
/// AltitudeService), ein zusätzlicher, eigener Positions-Stream wäre
/// unnötiger Ressourcenaufwand (weiterer GPS-Verbrauch).
class AltitudeReading {
  /// Höhe in Metern (i. d. R. bereits auf Meereshöhe bezogen, sofern das
  /// Betriebssystem das entsprechend aufbereitet - siehe Hinweis oben).
  final double altitudeMeters;

  /// Genauigkeit der Höhenangabe in Metern, sofern von der Plattform
  /// geliefert. null, wenn keine Angabe vorliegt.
  final double? altitudeAccuracyMeters;

  /// Breitengrad in Dezimalgrad (WGS84) - für die DMS-Positionsanzeige
  /// auf der Kompass-Seite (siehe CompassPage, util/coordinate_formatter.dart).
  final double latitude;

  /// Längengrad in Dezimalgrad (WGS84), analog zu [latitude].
  final double longitude;

  /// Horizontale Positionsgenauigkeit in Metern (bezieht sich auf
  /// [latitude]/[longitude], NICHT auf die Höhe - dafür siehe
  /// [altitudeAccuracyMeters]), sofern von der Plattform geliefert. null,
  /// wenn keine Angabe vorliegt.
  final double? positionAccuracyMeters;

  final DateTime timestamp;

  AltitudeReading({
    required this.altitudeMeters,
    required this.altitudeAccuracyMeters,
    required this.latitude,
    required this.longitude,
    required this.positionAccuracyMeters,
    required this.timestamp,
  });
}
