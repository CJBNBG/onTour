import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../models/altitude_reading.dart';

/// Ermittelt eine deutlich präzisere, rauschärmere Höhe über den
/// Luftdrucksensor (Barometer, Paket `sensors_plus`) - als Ergänzung zur
/// GPS-Höhe (siehe [AltitudeService]).
///
/// Ein Barometer liefert für sich genommen nur den ABSOLUTEN Luftdruck,
/// keine absolute Höhe - der Luftdruck auf Meereshöhe schwankt je nach
/// Wetterlage (grob 980-1050 hPa statt der oft als Faustregel
/// angenommenen "Standardatmosphäre" von 1013,25 hPa). Ein direkt aus dem
/// Luftdruck berechneter absoluter Höhenwert wäre daher ohne Weiteres um
/// mehrere Zehnermeter falsch.
///
/// DESHALB wird der Barometer laufend gegen die vom GPS gelieferte
/// absolute Höhe "kalibriert" (siehe [calibrate], wird von der
/// Kompass-Seite bei jeder neuen GPS-Höhenmessung erneut aufgerufen,
/// damit der Bezug nicht über längere Zeit wegdriftet - z. B. bei
/// Wetteränderungen während der Nutzung):
/// - GPS liefert die (grobe, aber absolute) Referenzhöhe.
/// - Der Barometer liefert danach sehr feine, praktisch rauschfreie
///   relative ÄNDERUNGEN gegenüber dieser Referenz (Auflösung im
///   Dezimeterbereich - deutlich besser als die 10-30 m Streuung
///   typischer GPS-Höhenwerte).
///
/// Das ist eine einfache, praktische Sensor-Fusion (kein vollwertiges
/// Kalman-Filter), aber für eine Höhenanzeige in einer Alltags-App ein
/// guter, robuster Kompromiss zwischen Aufwand und Nutzen.
class BarometerAltitudeService {
  /// Exponent der internationalen barometrischen Höhenformel.
  static const double _exponent = 1 / 5.255;

  StreamSubscription<BarometerEvent>? _subscription;
  StreamController<AltitudeReading>? _controller;

  double? _referencePressureHPa;
  double? _referenceAltitudeMeters;
  double? _referenceLatitude;
  double? _referenceLongitude;
  double? _referencePositionAccuracyMeters;
  double? _lastPressureHPa;

  /// true, sobald mindestens einmal kalibriert wurde (siehe [calibrate])
  /// - erst dann liefert [altitudeStream] tatsächlich Werte.
  bool get isCalibrated => _referencePressureHPa != null;

  /// Setzt/aktualisiert den Referenzpunkt für die Barometer-Berechnung.
  /// [referenceLatitude]/[referenceLongitude]/[referencePositionAccuracyMeters]
  /// werden NICHT für die eigentliche Höhenberechnung benötigt, sondern
  /// nur "durchgereicht" - der Barometer selbst kennt weder Position noch
  /// deren Genauigkeit, die von ihm erzeugten [AltitudeReading]s sollen
  /// aber trotzdem beides (die zuletzt bekannten GPS-Werte) für die
  /// Positionsanzeige auf der Kompass-Seite enthalten.
  /// [referencePressureHPa] kann weggelassen werden, dann wird der
  /// zuletzt vom Sensor gelieferte Druckwert verwendet (sofern bereits
  /// einer vorliegt).
  void calibrate({
    required double referenceAltitudeMeters,
    required double referenceLatitude,
    required double referenceLongitude,
    double? referencePositionAccuracyMeters,
    double? referencePressureHPa,
  }) {
    final pressure = referencePressureHPa ?? _lastPressureHPa;
    if (pressure == null) return; // noch kein Luftdruckwert vorhanden
    _referenceAltitudeMeters = referenceAltitudeMeters;
    _referenceLatitude = referenceLatitude;
    _referenceLongitude = referenceLongitude;
    _referencePositionAccuracyMeters = referencePositionAccuracyMeters;
    _referencePressureHPa = pressure;
  }

  Stream<AltitudeReading> altitudeStream() {
    _controller ??= StreamController<AltitudeReading>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    return _controller!.stream;
  }

  void _startListening() {
    _subscription = barometerEventStream().listen(
      (event) {
        _lastPressureHPa = event.pressure;
        final refPressure = _referencePressureHPa;
        final refAltitude = _referenceAltitudeMeters;
        if (refPressure == null || refAltitude == null) {
          // Noch nicht kalibriert - wartet auf die erste GPS-Höhe
          // (siehe calibrate()).
          return;
        }

        // Barometrische Höhenformel (internationale Höhenformel) für die
        // Höhen-DIFFERENZ gegenüber dem zuletzt gesetzten Referenzpunkt.
        final delta =
            44330.0 * (1 - math.pow(event.pressure / refPressure, _exponent));

        _controller?.add(AltitudeReading(
          altitudeMeters: refAltitude + delta,
          // Bezieht sich nur auf die (sehr feine) Sensorauflösung selbst -
          // die absolute Richtigkeit hängt weiterhin von der Güte der
          // letzten GPS-Kalibrierung ab, siehe Klassen-Dokumentation.
          altitudeAccuracyMeters: 0.3,
          // Position stammt vom letzten Kalibrierungszeitpunkt (siehe
          // calibrate()) - der Barometer selbst liefert keine eigene
          // Position, aktualisiert sich aber ohnehin bei jeder neuen
          // GPS-Höhenmessung erneut.
          latitude: _referenceLatitude!,
          longitude: _referenceLongitude!,
          positionAccuracyMeters: _referencePositionAccuracyMeters,
          timestamp: DateTime.now(),
        ));
      },
      onError: (Object error) {
        _controller?.addError(error);
      },
    );
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller?.close();
    _subscription = null;
    _controller = null;
    _referencePressureHPa = null;
    _referenceAltitudeMeters = null;
    _referenceLatitude = null;
    _referenceLongitude = null;
    _referencePositionAccuracyMeters = null;
    _lastPressureHPa = null;
  }
}
