/// Eine einzelne Geschwindigkeits-Messung, so wie sie vom
/// [SpeedService] geliefert wird - Rohwerte stets in m/s (SI-Einheit),
/// die Umrechnung in die vom Nutzer gewählte Anzeigeeinheit erfolgt erst
/// in der UI (siehe SpeedUnit.fromMetersPerSecond).
class SpeedReading {
  /// Geschwindigkeit in Metern pro Sekunde. Niemals negativ (auf 0
  /// begrenzt, siehe SpeedService - vereinzelt liefern Standortanbieter
  /// bei Messungenauigkeiten knapp negative Werte).
  final double speedMetersPerSecond;

  /// Geschwindigkeitsgenauigkeit in Metern pro Sekunde, sofern von der
  /// Plattform geliefert (auf iOS/Android ab bestimmten OS-Versionen
  /// verfügbar). null, wenn keine Angabe vorliegt.
  final double? speedAccuracyMetersPerSecond;

  final DateTime timestamp;

  SpeedReading({
    required this.speedMetersPerSecond,
    required this.speedAccuracyMetersPerSecond,
    required this.timestamp,
  });
}
