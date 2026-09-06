/// Ein einzelner GPS-Punkt innerhalb eines aufgezeichneten Tracks, wie er
/// vom `TrackRecordingService` gesammelt wird.
class TrackPoint {
  final double latitude;
  final double longitude;

  /// Höhe in Metern, sofern von der Plattform geliefert (siehe auch
  /// AltitudeReading für die generelle Ungenauigkeit von GPS-Höhenwerten).
  /// null, wenn keine Angabe vorliegt.
  final double? altitudeMeters;

  final DateTime timestamp;

  TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'alt': altitudeMeters,
        'ts': timestamp.toIso8601String(),
      };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        altitudeMeters: (json['alt'] as num?)?.toDouble(),
        timestamp: DateTime.parse(json['ts'] as String),
      );
}
