import 'dart:async';

import 'package:flutter/services.dart';

import 'diagnostic_log_service.dart';

/// Korrigiert die GPS-Höhe in zwei Stufen (siehe README Abschnitt 54):
///
/// 1. **NN-Korrektur (automatisch):** Ab Android 14 liefert `Location`
///    zusätzlich die Höhe über NN (MSL, `getMslAltitudeMeters`). Die
///    Differenz zur Höhe, die auch `geolocator` (`Position.altitude`)
///    verwendet, ist der Geoid-Versatz des Geräts. Liefert ein Gerät
///    `altitude` bereits als NN-Höhe, ergibt sich ein Versatz von ca. 0 -
///    die Korrektur passt sich damit automatisch an das jeweilige Gerät an.
///    Auf Geräten mit Android < 14 ist sie nicht verfügbar.
/// 2. **Manueller Versatz:** Vom Nutzer über die Kompass-Seite ermittelt
///    (bekannte Höhe eingeben). Wird nur auf den ANGEZEIGTEN/gespeicherten
///    Endwert addiert, nicht auf die Barometer-Referenz, damit er sofort
///    wirkt und nicht erst über den langsamen Tiefpass nachgeführt wird.
class AltitudeCorrection {
  AltitudeCorrection._();

  static final AltitudeCorrection instance = AltitudeCorrection._();

  static const MethodChannel _channel = MethodChannel('ontour/altitude');

  /// Geoid-Undulation liegt weltweit zwischen ca. -106 m und +85 m;
  /// alles darüber ist ein Messfehler und wird verworfen.
  static const double _maxPlausibleCorrectionMeters = 110;

  static const Duration _refreshInterval = Duration(minutes: 5);
  static const Duration _retryInterval = Duration(seconds: 20);

  /// Vom Nutzer ermittelter Versatz (m), gesetzt von AppPreferences.
  double manualOffsetMeters = 0;

  double? _mslCorrectionMeters;

  /// Zuletzt vom System gemeldete Rohwerte (nur für die Anzeige im
  /// Kalibrierdialog und das Diagnose-Protokoll).
  double? lastNativeAltitudeMeters;
  double? lastMslAltitudeMeters;
  double? lastMslAccuracyMeters;

  bool _unsupported = false;
  bool _busy = false;
  DateTime? _lastAttemptAt;

  /// false, wenn das Gerät die NN-Höhe nicht liefern kann (Android < 14).
  bool get mslSupported => !_unsupported;

  /// true, sobald eine NN-Korrektur ermittelt wurde.
  bool get hasMslCorrection => _mslCorrectionMeters != null;

  /// Aktuelle NN-Korrektur in Metern (0, solange keine vorliegt).
  double get mslCorrectionMeters => _mslCorrectionMeters ?? 0;

  /// GPS-Höhe nach NN-Korrektur - dient auch als Referenz für den
  /// Barometer.
  double gpsReference(double rawGpsAltitude) => rawGpsAltitude + mslCorrectionMeters;

  /// Endwert für Anzeige und Track: zusätzlich um den manuellen Versatz
  /// verschoben.
  double display(double correctedAltitude) => correctedAltitude + manualOffsetMeters;

  /// Fragt - höchstens alle paar Minuten - die native Seite nach der
  /// NN-Höhe. Fire-and-forget: Fehler werden verschluckt.
  /// [dartAltitude] (Position.altitude) und [shownAltitude] dienen nur dem
  /// Diagnose-Protokoll.
  Future<void> refreshIfDue({double? dartAltitude, double? shownAltitude}) async {
    if (_unsupported || _busy) return;
    final last = _lastAttemptAt;
    final interval = hasMslCorrection ? _refreshInterval : _retryInterval;
    if (last != null && DateTime.now().difference(last) < interval) return;

    _busy = true;
    _lastAttemptAt = DateTime.now();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('mslAltitude');
      if (result == null) return;
      if (result['supported'] == false) {
        _unsupported = true;
        unawaited(DiagnosticLogService.instance.log('Höhe: NN-Höhe vom System nicht verfügbar (Android < 14)'));
        return;
      }
      if (result['hasFix'] != true) return;

      final native = (result['altitude'] as num?)?.toDouble();
      final msl = (result['msl'] as num?)?.toDouble();
      if (native == null || msl == null || !native.isFinite || !msl.isFinite) return;

      final correction = msl - native;
      lastNativeAltitudeMeters = native;
      lastMslAltitudeMeters = msl;
      lastMslAccuracyMeters = (result['mslAccuracy'] as num?)?.toDouble();
      if (correction.abs() > _maxPlausibleCorrectionMeters) {
        unawaited(DiagnosticLogService.instance.log('Höhe: unplausible NN-Korrektur ${correction.toStringAsFixed(1)} m verworfen'));
        return;
      }
      _mslCorrectionMeters = correction;
      unawaited(DiagnosticLogService.instance.log(
        'Höhe: Android altitude=${native.toStringAsFixed(1)} m, '
        'MSL=${msl.toStringAsFixed(1)} m, Korrektur=${correction.toStringAsFixed(1)} m, '
        'Position.altitude=${dartAltitude?.toStringAsFixed(1) ?? '-'} m, '
        'angezeigt=${shownAltitude?.toStringAsFixed(1) ?? '-'} m, '
        'manueller Versatz=${manualOffsetMeters.toStringAsFixed(1)} m',
      ));
    } catch (_) {
      // Reiner Zusatz - ohne native Seite bleibt es bei der GPS-Höhe.
    } finally {
      _busy = false;
    }
  }
}
