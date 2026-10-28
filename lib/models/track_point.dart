/// Ein einzelner GPS-Punkt innerhalb eines aufgezeichneten Tracks, wie er
/// vom `TrackRecordingService` gesammelt wird.
class TrackPoint {
  final double latitude;
  final double longitude;

  /// Höhe in Metern, sofern von der Plattform geliefert (siehe auch
  /// AltitudeReading für die generelle Ungenauigkeit von GPS-Höhenwerten).
  /// null, wenn keine Angabe vorliegt. Seit README Abschnitt 27 bevorzugt
  /// die gegen GPS kalibrierte Barometer-Höhe, sofern das Gerät ein
  /// Barometer besitzt (siehe TrackRecordingService).
  final double? altitudeMeters;

  /// NEU (siehe README Abschnitt 29): vom Gerät zum Zeitpunkt dieses
  /// Punkts gemessene Momentan-Geschwindigkeit in Metern pro Sekunde
  /// (`Position.speed`, negative Messrauschen-Werte bereits auf 0
  /// begrenzt - siehe TrackRecordingService._onPosition, analog zu
  /// SpeedService). null, wenn keine Angabe vorliegt (z. B. bei aus GPX
  /// importierten Tracks, siehe Abschnitt 20 - GPX kennt kein
  /// Standardfeld für die Geschwindigkeit; TrackProfileCalculator
  /// schätzt die Geschwindigkeit in diesem Fall ersatzweise aus Distanz/
  /// Zeit zum vorherigen Punkt).
  final double? speedMetersPerSecond;

  final DateTime timestamp;

  TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.speedMetersPerSecond,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'alt': altitudeMeters,
        'spd': speedMetersPerSecond,
        'ts': timestamp.toIso8601String(),
      };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        altitudeMeters: (json['alt'] as num?)?.toDouble(),
        // Fallback null für vor README Abschnitt 29 gespeicherte Dateien -
        // dort existierte das Feld noch nicht.
        speedMetersPerSecond: (json['spd'] as num?)?.toDouble(),
        timestamp: DateTime.parse(json['ts'] as String),
      );
}
