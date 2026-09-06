import 'track_point.dart';

/// Ein abgeschlossener, aufgezeichneter Track: Name, Zeitraum sowie alle
/// gesammelten [TrackPoint]s. Wird vom `TrackRecordingService` beim
/// Beenden einer Aufzeichnung erzeugt und vom `TrackStorageService` als
/// JSON-Datei persistiert.
class RecordedTrack {
  /// Eindeutige ID - die Millisekunden des Startzeitpunkts seit der
  /// Unix-Epoche, gleichzeitig als Dateiname für die Persistierung
  /// verwendet (siehe TrackStorageService). Das ist eindeutig genug für
  /// eine App mit lokal auf einem Gerät gespeicherten Tracks (zwei
  /// Aufzeichnungen können nicht in derselben Millisekunde starten).
  final String id;

  final String name;
  final DateTime startTime;
  final DateTime endTime;
  final List<TrackPoint> points;

  /// Gesamtstrecke in Metern - wird während der Aufzeichnung fortlaufend
  /// aus den einzelnen Punktabständen aufsummiert (siehe
  /// TrackRecordingService), NICHT erst beim Speichern aus [points] neu
  /// berechnet, damit auch bei sehr vielen Punkten keine spürbare
  /// Verzögerung beim Beenden der Aufzeichnung entsteht.
  final double distanceMeters;

  /// Tatsächliche Aufzeichnungsdauer (Pausen bereits herausgerechnet,
  /// siehe TrackRecordingService.elapsed) - bewusst NICHT einfach
  /// endTime.difference(startTime), da das Pausen mit einschließen würde.
  final Duration recordedDuration;

  RecordedTrack({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.points,
    required this.distanceMeters,
    required this.recordedDuration,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'distanceMeters': distanceMeters,
        'recordedDurationSeconds': recordedDuration.inSeconds,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory RecordedTrack.fromJson(Map<String, dynamic> json) => RecordedTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        recordedDuration: Duration(
          seconds: (json['recordedDurationSeconds'] as num?)?.toInt() ??
              // Fallback für evtl. aeltere, vor Einfuehrung dieses Felds
              // gespeicherte Dateien - dann Start/Ende-Differenz nutzen.
              DateTime.parse(json['endTime'] as String)
                  .difference(DateTime.parse(json['startTime'] as String))
                  .inSeconds,
        ),
        points: (json['points'] as List)
            .map((p) => TrackPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
