import 'package:geolocator/geolocator.dart';

import '../models/track_point.dart';

/// Ein einzelner, aufbereiteter Datenpunkt für die Profil-Diagramme (siehe
/// README Abschnitt 29) - entspricht einem [TrackPoint], ergänzt um
/// abgeleitete Werte (kumulierte Distanz, Höhenänderung seit Start,
/// Steigung/Gefälle) sowie einer Geschwindigkeits-Schätzung, falls der
/// zugrunde liegende Punkt selbst keine besitzt.
class TrackProfilePoint {
  /// Kumulierte Streckenlänge seit dem ersten Punkt, in Metern - dient als
  /// gemeinsame x-Achse aller vier Profil-Diagramme (siehe
  /// TrackProfileCharts). Distanz statt Zeit, da sie für ein
  /// Höhen-/Steigungsprofil die im Outdoor-Bereich gebräuchlichere,
  /// anschaulichere Achse ist (vergleichbar mit Höhenprofilen auf
  /// Wander-/Radkarten).
  final double distanceMeters;

  /// Momentan-Geschwindigkeit in m/s - vom Gerät gemessen (siehe
  /// TrackPoint.speedMetersPerSecond), ersatzweise aus Distanz/Zeit zum
  /// vorherigen Punkt geschätzt, falls nicht vorhanden (siehe
  /// [_estimateSpeed], z. B. bei importierten GPX-Tracks). null nur, wenn
  /// beides nicht möglich ist (erster Punkt einer Aufzeichnung ohne
  /// eigenen Geschwindigkeitswert).
  final double? speedMetersPerSecond;

  /// Absolute Höhe in Metern über Normal-Null, direkt von [TrackPoint]
  /// übernommen (siehe dort für die Quelle - GPS oder Barometer).
  final double? altitudeMeters;

  /// Höhenänderung gegenüber dem ERSTEN Punkt der Aufzeichnung, in Metern
  /// - kann negativ werden (siehe README Abschnitt 29, "Netto-
  /// Höhenänderung"). null, wenn für diesen oder den ersten Punkt keine
  /// Höhe vorliegt.
  final double? netAltitudeChangeMeters;

  /// Steigung (positiv) bzw. Gefälle (negativ) in Prozent, wie im
  /// Straßenverkehr üblich angegeben (Höhendifferenz durch horizontale
  /// Distanz, mal 100) - siehe [_estimateGradient] für die
  /// Berechnungsdetails inkl. Rauschunterdrückung. null, wenn (noch)
  /// nicht berechenbar.
  final double? gradientPercent;

  const TrackProfilePoint({
    required this.distanceMeters,
    required this.speedMetersPerSecond,
    required this.altitudeMeters,
    required this.netAltitudeChangeMeters,
    required this.gradientPercent,
  });
}

/// Wandelt die während einer Aufzeichnung gesammelten (oder aus einer
/// gespeicherten/importierten Datei geladenen) [TrackPoint]s in eine Liste
/// von [TrackProfilePoint]s um - die gemeinsame Datengrundlage für die
/// Momentanwerte-Anzeige UND die vier Profil-Diagramme auf dem
/// Details-Tab von TrackPage (laufende Aufzeichnung) und TrackDetailPage
/// (gespeicherter Track), siehe README Abschnitt 29.
///
/// Bewusst als reine, zustandslose Umwandlungslogik ohne UI-Bezug
/// gehalten - analog zu GpxConverter (Abschnitt 20) oder
/// CoordinateFormatter (Abschnitt 25).
class TrackProfileCalculator {
  /// Mindest-Streckenlänge (Meter) des Auswertefensters, ab der überhaupt
  /// eine Steigung/Gefälle berechnet wird - bei sehr kurzen Strecken
  /// würden schon kleine Höhen-Messungenauigkeiten zu unrealistisch großen
  /// Prozentwerten hochgerechnet (kleiner Nenner).
  static const double _minGradientSegmentMeters = 20.0;

  /// Länge (Meter) des rückwärtigen Fensters, über das die Steigung per
  /// linearer Regression (Ausgleichsgerade Höhe über Distanz) bestimmt
  /// wird - glättet Rauschen und einzelne Ausreißer deutlich besser als
  /// die Differenz zweier einzelner Punkte (siehe README Abschnitt 44).
  static const double _gradientWindowMeters = 50.0;

  /// Prozentwerte werden auf diesen Betrag gedeckelt - realistische
  /// Straßen-/Wandersteigungen liegen praktisch immer deutlich darunter;
  /// der Deckel verhindert, dass ein einzelner Messausreißer die gesamte
  /// Diagramm-Skala verzerrt.
  static const double _maxAbsGradientPercent = 40.0;

  static List<TrackProfilePoint> compute(List<TrackPoint> points) {
    if (points.isEmpty) return const [];

    // Kumulierte Distanz je Punkt vorab berechnen - wird sowohl als
    // x-Achsen-Wert als auch für die Geschwindigkeits-/Steigungs-
    // Schätzung mehrfach benötigt.
    final cumulativeDistances = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      cumulativeDistances[i] = cumulativeDistances[i - 1] +
          Geolocator.distanceBetween(
            points[i - 1].latitude,
            points[i - 1].longitude,
            points[i].latitude,
            points[i].longitude,
          );
    }

    final startAltitude = points.first.altitudeMeters;

    return [
      for (var i = 0; i < points.length; i++)
        TrackProfilePoint(
          distanceMeters: cumulativeDistances[i],
          speedMetersPerSecond:
              points[i].speedMetersPerSecond ?? _estimateSpeed(points, cumulativeDistances, i),
          altitudeMeters: points[i].altitudeMeters,
          netAltitudeChangeMeters: (points[i].altitudeMeters != null && startAltitude != null)
              ? points[i].altitudeMeters! - startAltitude
              : null,
          gradientPercent: _estimateGradient(points, cumulativeDistances, i),
        ),
    ];
  }

  /// Ersatzweise Geschwindigkeit aus Distanz/Zeit zum VORHERIGEN Punkt,
  /// für Punkte ohne eigene, vom Gerät gemessene Geschwindigkeit (siehe
  /// TrackPoint.speedMetersPerSecond - insbesondere bei aus GPX
  /// importierten Tracks, GPX kennt kein Standardfeld dafür, siehe
  /// Abschnitt 20).
  static double? _estimateSpeed(
    List<TrackPoint> points,
    List<double> cumulativeDistances,
    int index,
  ) {
    if (index == 0) return null;
    final deltaDistanceMeters = cumulativeDistances[index] - cumulativeDistances[index - 1];
    final deltaSeconds =
        points[index].timestamp.difference(points[index - 1].timestamp).inMilliseconds / 1000;
    if (deltaSeconds <= 0) return null;
    return deltaDistanceMeters / deltaSeconds;
  }

  /// Steigung/Gefälle in Prozent am Punkt [index] - Steigung der
  /// Ausgleichsgeraden (lineare Regression) von Höhe über Distanz über alle
  /// Punkte der letzten [_gradientWindowMeters] bis einschließlich
  /// [index]. Das Fenster muss mindestens [_minGradientSegmentMeters]
  /// lang sein, sonst null.
  static double? _estimateGradient(
    List<TrackPoint> points,
    List<double> cumulativeDistances,
    int index,
  ) {
    if (points[index].altitudeMeters == null) return null;

    final xs = <double>[];
    final ys = <double>[];
    for (var j = index; j >= 0; j--) {
      final distanceBack = cumulativeDistances[index] - cumulativeDistances[j];
      if (distanceBack > _gradientWindowMeters) break;
      final altitude = points[j].altitudeMeters;
      if (altitude == null) continue;
      xs.add(cumulativeDistances[j]);
      ys.add(altitude);
    }
    if (xs.length < 2) return null;

    final span = xs.first - xs.last;
    if (span < _minGradientSegmentMeters) return null;

    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < xs.length; i++) {
      numerator += (xs[i] - meanX) * (ys[i] - meanY);
      denominator += (xs[i] - meanX) * (xs[i] - meanX);
    }
    if (denominator <= 0) return null;

    final gradient = numerator / denominator * 100;
    return gradient.clamp(-_maxAbsGradientPercent, _maxAbsGradientPercent);
  }
}
