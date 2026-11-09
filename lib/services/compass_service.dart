import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/compass_reading.dart';

/// Kapselt den Zugriff auf den Magnetkompass des Geräts (Paket
/// `flutter_compass`), korrigiert um die Missweisung (Deklination) auf
/// geografisch Nord.
///
/// NEU (siehe README Abschnitt 39): Der Kurs wird zusätzlich über eine
/// Sensorfusion mit dem Gyroskop stabilisiert (Complementary Filter) und
/// um eine Störungserkennung über die Magnetfeldstärke ergänzt.
class CompassService {
  static const MethodChannel _geomagneticChannel = MethodChannel('ontour/geomagnetic');

  /// Missweisung (Deklination) in Grad - positiv, wenn magnetisch Nord
  /// oestlich von geografisch Nord liegt. 0, solange noch nicht ermittelt;
  /// dann bleibt es beim magnetischen Kurs wie bisher.
  double _declinationDegrees = 0;

  /// true, sobald die Missweisung tatsächlich ermittelt wurde (siehe
  /// [updateDeclination]) - vorher ist der Kurs noch der magnetische.
  bool _hasDeclination = false;

  /// Aktuell angewandte Missweisung in Grad (positiv = magnetisch Nord
  /// liegt östlich von geografisch Nord, d. h. Ostmissweisung) - null,
  /// solange sie noch nicht ermittelt werden konnte. Für die Anzeige auf
  /// der Kompass-Seite.
  double? get declinationDegrees => _hasDeclination ? _declinationDegrees : null;

  /// Ermittelt nativ (Android GeomagneticField, offline) die Deklination
  /// fuer den Standort - danach liefert [readingStream] den auf
  /// geografisch Nord korrigierten Kurs.
  Future<void> updateDeclination({
    required double latitude,
    required double longitude,
    double altitude = 0,
  }) async {
    try {
      final value = await _geomagneticChannel.invokeMethod<double>('declination', {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
      });
      if (value != null) {
        _declinationDegrees = value;
        _hasDeclination = true;
      }
    } catch (_) {
      // Reiner Zusatz - bei Fehlschlag bleibt es beim magnetischen Kurs.
    }
  }

  /// true, wenn das Gerät über einen Kompass-Sensor verfügt. Sollte vor
  /// dem Abonnieren von [readingStream] geprüft werden (manche Geräte,
  /// insbesondere reine WLAN-Tablets, besitzen keinen Magnetometer).
  bool get isSupported => FlutterCompass.events != null;

  // ==== Filter-Parameter (empirische Startwerte, ggf. nachjustieren) ====

  /// Zeitkonstante, mit der der Kurs zum Magnetkurs gezogen wird.
  static const double _correctionTimeConstantS = 1.5;

  /// Plausibler Bereich der Erdmagnetfeldstärke (normal ca. 25-65 µT,
  /// mit Toleranz).
  static const double _minFieldMicroTesla = 20;
  static const double _maxFieldMicroTesla = 75;

  /// Relative Abweichung von der langsam mitlaufenden Basis.
  static const double _maxBaselineDeviation = 0.30;

  /// Entprellung des Störungszustands (analog zu MotionService).
  static const Duration _enterDisturbedAfter = Duration(seconds: 1);
  static const Duration _leaveDisturbedAfter = Duration(seconds: 2);

  /// Weichen Gyro- und Magnetkurs bei ungestörtem Feld so lange um mehr
  /// als [_disagreementDegrees] ab, obwohl das Gerät fast still gehalten
  /// wird ([_stillRateDegPerS]), wird neu synchronisiert (Gyro-Drift).
  static const Duration _resyncAfterDisagreement = Duration(seconds: 8);
  static const double _disagreementDegrees = 30;
  static const double _stillRateDegPerS = 10;

  static const double _gravityAlpha = 0.1;
  static const double _fieldAlpha = 0.2;
  static const double _baselineAlpha = 0.002;
  static const Duration _emitInterval = Duration(milliseconds: 50);

  StreamController<CompassReading>? _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Stopwatch _clock = Stopwatch();

  double? _fusedHeading;
  double? _measuredHeading;
  double? _accuracy;
  int? _lastGyroMicros;
  bool _gyroActive = false;

  double _gx = 0, _gy = 0, _gz = 0;
  bool _hasGravity = false;

  double? _fieldSmoothed;
  double? _fieldBaseline;
  bool _disturbed = false;
  Duration? _candidateSince;
  Duration? _disagreementSince;
  Duration _lastEmit = Duration.zero;

  Stream<CompassReading> readingStream() {
    if (!isSupported) return const Stream.empty();
    _controller ??= StreamController<CompassReading>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return _controller!.stream;
  }

  void _start() {
    _clock
      ..reset()
      ..start();

    _subscriptions.add(FlutterCompass.events!.listen(
      (event) {
        final heading = event.heading;
        if (heading == null) return;
        // Magnetkurs bereits auf geografisch Nord korrigiert, damit die
        // Fusion durchgehend im selben Bezugssystem arbeitet.
        final h = _normalize(heading + _declinationDegrees);
        _measuredHeading = h;
        _accuracy = event.accuracy;
        if (_fusedHeading == null || !_gyroActive) {
          // Erster Wert bzw. kein Gyroskop vorhanden: durchreichen.
          _fusedHeading = h;
          _emit();
        }
      },
      onError: (Object error) {},
    ));

    // Fehler (Sensor fehlt) werden bewusst verschluckt: Ohne Gyro bleibt
    // es beim reinen Magnetkurs, ohne Magnetometer gibt es keine
    // Störungswarnung.
    _subscriptions.add(accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(_onAccelerometer, onError: (Object error) {}));
    _subscriptions.add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
        .listen(_onGyroscope, onError: (Object error) {}));
    _subscriptions.add(magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen(_onMagnetometer, onError: (Object error) {}));
  }

  void _stop() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _clock.stop();
    _fusedHeading = null;
    _measuredHeading = null;
    _accuracy = null;
    _lastGyroMicros = null;
    _gyroActive = false;
    _hasGravity = false;
    _fieldSmoothed = null;
    _fieldBaseline = null;
    _disturbed = false;
    _candidateSince = null;
    _disagreementSince = null;
    _lastEmit = Duration.zero;
  }

  Future<void> dispose() async {
    _stop();
    await _controller?.close();
    _controller = null;
  }

  // ==== Sensor-Handler ====

  void _onAccelerometer(AccelerometerEvent e) {
    if (!_hasGravity) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
      _hasGravity = true;
      return;
    }
    // Tiefpass isoliert die Erdanziehung von Bewegungsbeschleunigung.
    _gx += _gravityAlpha * (e.x - _gx);
    _gy += _gravityAlpha * (e.y - _gy);
    _gz += _gravityAlpha * (e.z - _gz);
  }

  void _onGyroscope(GyroscopeEvent e) {
    final now = _clock.elapsedMicroseconds;
    final last = _lastGyroMicros;
    _lastGyroMicros = now;
    if (last == null) return;
    final dt = (now - last) / 1e6;

    final fused = _fusedHeading;
    if (fused == null || !_hasGravity || dt <= 0 || dt > 0.5) return;
    final gNorm = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (gNorm < 1) return; // z. B. Freifall - keine verlässliche Lotrichtung

    _gyroActive = true;

    // Drehrate um die Lotrichtung (rad/s, gegen den Uhrzeigersinn von
    // oben gesehen) - unabhängig von der Geräteneigung. Der Kurs läuft
    // im Uhrzeigersinn, daher das Minus.
    final yawRateUp = (e.x * _gx + e.y * _gy + e.z * _gz) / gNorm;
    final headingRateDeg = -yawRateUp * 180 / math.pi;

    var h = fused + headingRateDeg * dt;

    final measured = _measuredHeading;
    if (measured != null) {
      final error = _angleDiff(measured, h);
      // Bei gestörtem Feld keine Korrektur zum Magnetkurs - der Kurs
      // läuft dann nur auf dem Gyro weiter.
      final gain = _disturbed ? 0.0 : dt / (_correctionTimeConstantS + dt);
      h += error * gain;

      if (!_disturbed &&
          error.abs() > _disagreementDegrees &&
          headingRateDeg.abs() < _stillRateDegPerS) {
        final since = _disagreementSince ??= _clock.elapsed;
        if (_clock.elapsed - since >= _resyncAfterDisagreement) {
          h = measured; // Gyro-Drift: neu auf den Magnetkurs setzen
          _disagreementSince = null;
        }
      } else {
        _disagreementSince = null;
      }
    }

    _fusedHeading = _normalize(h);
    _emit();
  }

  void _onMagnetometer(MagnetometerEvent e) {
    final strength = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final previous = _fieldSmoothed;
    final smoothed = previous == null ? strength : previous + _fieldAlpha * (strength - previous);
    _fieldSmoothed = smoothed;

    final baseline = _fieldBaseline ?? smoothed;
    final outOfRange = smoothed < _minFieldMicroTesla || smoothed > _maxFieldMicroTesla;
    final deviates = baseline > 0 && (smoothed - baseline).abs() / baseline > _maxBaselineDeviation;
    final bad = outOfRange || deviates;

    // Basis nur im ungestörten Zustand nachführen.
    _fieldBaseline = bad ? baseline : baseline + _baselineAlpha * (smoothed - baseline);

    _updateDisturbed(bad);
  }

  /// Entprellter Zustandswechsel (analog zu MotionService).
  void _updateDisturbed(bool bad) {
    if (bad == _disturbed) {
      _candidateSince = null;
      return;
    }
    final now = _clock.elapsed;
    final since = _candidateSince ??= now;
    final needed = bad ? _enterDisturbedAfter : _leaveDisturbedAfter;
    if (now - since >= needed) {
      _disturbed = bad;
      _candidateSince = null;
      _emit(force: true);
    }
  }

  void _emit({bool force = false}) {
    final heading = _fusedHeading;
    if (heading == null) return;
    final now = _clock.elapsed;
    if (!force && now - _lastEmit < _emitInterval) return;
    _lastEmit = now;
    _controller?.add(CompassReading(
      headingDegrees: heading,
      accuracyDegrees: _accuracy,
      isDisturbed: _disturbed,
      fieldStrengthMicroTesla: _fieldSmoothed,
    ));
  }

  // ==== Winkel-Hilfen ====

  /// Normalisiert einen Winkel auf den Bereich [0, 360). Dart-`%` liefert
  /// bei positivem Teiler nie negative Werte - stellt (wie die frühere
  /// Fassung, siehe README Abschnitt 10) sicher, dass NIE ein negativer
  /// Kurs angezeigt wird.
  static double _normalize(double degrees) => degrees % 360;

  /// Kürzeste Winkeldifferenz target - current, in (-180, 180].
  static double _angleDiff(double target, double current) {
    var d = (target - current) % 360;
    if (d > 180) d -= 360;
    return d;
  }
}
