import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../models/altitude_reading.dart';

class _PressureSample {
  final DateTime time;
  final double hPa;
  const _PressureSample(this.time, this.hPa);
}

/// Ermittelt eine deutlich präzisere, rauschärmere Höhe über den
/// Luftdrucksensor (Barometer, Paket `sensors_plus`) - als Ergänzung zur
/// GPS-Höhe (siehe [AltitudeService]).
///
/// Ein Barometer liefert für sich genommen nur den ABSOLUTEN Luftdruck,
/// keine absolute Höhe - der Luftdruck auf Meereshöhe schwankt je nach
/// Wetterlage. Ein direkt aus dem Luftdruck berechneter absoluter Höhenwert
/// wäre daher ohne Weiteres um mehrere Zehnermeter falsch.
///
/// SENSOR-FUSION (überarbeitet, siehe README Abschnitt 44):
/// - Der Barometer liefert sehr feine, praktisch rauschfreie relative
///   ÄNDERUNGEN gegenüber einem FESTEN Referenzpunkt (erste Kalibrierung).
///   Der Druck wird dafür über ein kurzes Zeitfenster (3 s) gemittelt.
/// - GPS liefert die grobe, aber absolute Höhe. Der Versatz zwischen
///   Barometer-Höhe und GPS-Höhe wird NICHT hart überschrieben, sondern
///   über einen Tiefpass LANGSAM nachgeführt (Zeitkonstante 120 s, am
///   Anfang als laufender Mittelwert der ersten Messungen). Dadurch gibt es
///   keine Stufen/Sprünge mehr (GPS-Rauschen von 10-30 m schlägt nicht auf
///   die Anzeige durch), wetterbedingte Luftdruckdrift wird aber trotzdem
///   ausgeglichen.
///
/// Das ist eine einfache, praktische Sensor-Fusion (komplementärer Filter,
/// kein vollwertiges Kalman-Filter).
class BarometerAltitudeService {
  /// Exponent der internationalen barometrischen Höhenformel.
  static const double _exponent = 1 / 5.255;

  /// Zeitfenster, über das der Luftdruck gemittelt wird.
  static const Duration _pressureSmoothingWindow = Duration(seconds: 3);

  /// Zeitkonstante (Sekunden), mit der der Versatz zur GPS-Höhe
  /// nachgeführt wird - GPS-Rauschen wird dadurch über mehrere Minuten
  /// gemittelt, Wetterdrift (grob < 10 m pro Stunde) trotzdem verfolgt.
  static const double _offsetTimeConstantSeconds = 120;

  StreamSubscription<BarometerEvent>? _subscription;
  StreamController<AltitudeReading>? _controller;

  final List<_PressureSample> _pressureSamples = [];
  double? _smoothedPressureHPa;

  /// Fester Referenzpunkt (erste Kalibrierung).
  double? _referencePressureHPa;
  double? _referenceAltitudeMeters;

  /// Langsam nachgeführter Versatz zwischen Barometer-Höhe (relativ zum
  /// Referenzpunkt) und der GPS-Höhe.
  double _offsetMeters = 0;
  int _offsetSampleCount = 0;
  DateTime? _lastOffsetUpdateAt;

  double? _referenceLatitude;
  double? _referenceLongitude;
  double? _referencePositionAccuracyMeters;

  /// true, sobald mindestens einmal kalibriert wurde (siehe [calibrate])
  /// - erst dann liefert [altitudeStream] tatsächlich Werte.
  bool get isCalibrated => _referencePressureHPa != null;

  /// Wird bei jeder neuen GPS-Höhenmessung aufgerufen. Die erste Messung
  /// legt den festen Referenzpunkt fest, jede weitere führt nur den
  /// Versatz zur GPS-Höhe langsam nach (siehe Klassenkommentar).
  /// [referenceLatitude]/[referenceLongitude]/[referencePositionAccuracyMeters]
  /// werden NICHT für die Höhenberechnung benötigt, sondern nur
  /// "durchgereicht" (Positionsanzeige auf der Kompass-Seite) und bei
  /// jedem Aufruf aktualisiert.
  /// [referencePressureHPa] kann weggelassen werden, dann wird der
  /// gemittelte Sensor-Druck verwendet (sofern bereits einer vorliegt).
  void calibrate({
    required double referenceAltitudeMeters,
    required double referenceLatitude,
    required double referenceLongitude,
    double? referencePositionAccuracyMeters,
    double? referencePressureHPa,
  }) {
    final pressure = referencePressureHPa ?? _smoothedPressureHPa;
    if (pressure == null) return; // noch kein Luftdruckwert vorhanden

    _referenceLatitude = referenceLatitude;
    _referenceLongitude = referenceLongitude;
    _referencePositionAccuracyMeters = referencePositionAccuracyMeters;

    final now = DateTime.now();
    final refPressure = _referencePressureHPa;
    final refAltitude = _referenceAltitudeMeters;
    if (refPressure == null || refAltitude == null) {
      // Erste Kalibrierung: fester Referenzpunkt, Versatz startet bei 0.
      _referencePressureHPa = pressure;
      _referenceAltitudeMeters = referenceAltitudeMeters;
      _offsetMeters = 0;
      _offsetSampleCount = 1;
      _lastOffsetUpdateAt = now;
      return;
    }

    // Soll-Versatz: Differenz zwischen GPS-Höhe und der reinen
    // Barometer-Höhe (relativ zum festen Referenzpunkt).
    final target = referenceAltitudeMeters - _rawBarometricAltitude(pressure);
    final last = _lastOffsetUpdateAt ?? now;
    final dtSeconds = now.difference(last).inMilliseconds / 1000;
    // Anfangs laufender Mittelwert (1/(n+1)), später exponentieller
    // Tiefpass - je nachdem, welcher Faktor größer ist.
    final timeAlpha = 1 - math.exp(-dtSeconds / _offsetTimeConstantSeconds);
    final alpha = math.max(timeAlpha, 1 / (_offsetSampleCount + 1));
    _offsetMeters += (target - _offsetMeters) * alpha;
    _offsetSampleCount++;
    _lastOffsetUpdateAt = now;
  }

  /// Höhe nur aus Druckdifferenz zum Referenzpunkt (ohne GPS-Versatz).
  double _rawBarometricAltitude(double pressureHPa) {
    final refPressure = _referencePressureHPa!;
    final refAltitude = _referenceAltitudeMeters!;
    // Barometrische Höhenformel (internationale Höhenformel) für die
    // Höhen-DIFFERENZ gegenüber dem Referenzpunkt.
    final delta = 44330.0 * (1 - math.pow(pressureHPa / refPressure, _exponent));
    return refAltitude + delta;
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
        final now = DateTime.now();
        _pressureSamples.add(_PressureSample(now, event.pressure));
        _pressureSamples.removeWhere(
          (s) => now.difference(s.time) > _pressureSmoothingWindow,
        );
        var sum = 0.0;
        for (final s in _pressureSamples) {
          sum += s.hPa;
        }
        final smoothed = sum / _pressureSamples.length;
        _smoothedPressureHPa = smoothed;

        if (_referencePressureHPa == null || _referenceAltitudeMeters == null) {
          // Noch nicht kalibriert - wartet auf die erste GPS-Höhe
          // (siehe calibrate()).
          return;
        }

        _controller?.add(AltitudeReading(
          altitudeMeters: _rawBarometricAltitude(smoothed) + _offsetMeters,
          // Bezieht sich nur auf die (sehr feine) Sensorauflösung selbst -
          // die absolute Richtigkeit hängt weiterhin von der Güte der
          // GPS-Referenz ab, siehe Klassen-Dokumentation.
          altitudeAccuracyMeters: 0.3,
          // Position stammt von der letzten GPS-Messung (siehe
          // calibrate()) - der Barometer selbst liefert keine eigene
          // Position.
          latitude: _referenceLatitude!,
          longitude: _referenceLongitude!,
          positionAccuracyMeters: _referencePositionAccuracyMeters,
          timestamp: now,
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
    _pressureSamples.clear();
    _smoothedPressureHPa = null;
    _referencePressureHPa = null;
    _referenceAltitudeMeters = null;
    _offsetMeters = 0;
    _offsetSampleCount = 0;
    _lastOffsetUpdateAt = null;
    _referenceLatitude = null;
    _referenceLongitude = null;
    _referencePositionAccuracyMeters = null;
  }
}
