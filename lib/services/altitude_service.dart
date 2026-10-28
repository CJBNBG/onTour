import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/altitude_reading.dart';

/// Ermittelt die aktuelle Höhe des Geräts über GPS (Paket `geolocator`,
/// `Position.altitude`) - für die Höhenanzeige auf der Kompass-Seite.
///
/// Bewusst als eigener, schlanker Service getrennt von [SpeedService]:
/// Die Höhe muss nicht so häufig aktualisiert werden wie die
/// Geschwindigkeit (deshalb ein moderater, fester `distanceFilter` statt
/// der auf der Tacho-Seite einstellbaren Genauigkeitsstufen) und soll
/// unabhängig davon funktionieren, ob die Tacho-Seite gerade überhaupt
/// benutzt wird.
class AltitudeService {
  /// NEU (siehe README Abschnitt 37): Öffentlich, damit die
  /// Genauigkeits-Anzeige auf der Kompass-Seite (`AccuracyBadge`) die
  /// hier tatsächlich fest verwendete Genauigkeit anzeigen kann, ohne
  /// sie ein zweites Mal (und damit potenziell abweichend) zu
  /// duplizieren.
  static const LocationAccuracy fixedAccuracy = LocationAccuracy.medium;

  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: fixedAccuracy,
    distanceFilter: 5,
  );

  StreamSubscription<Position>? _subscription;
  StreamController<AltitudeReading>? _controller;

  /// Prüft (und fragt bei Bedarf an), ob Standortdienst und -berechtigung
  /// für die Höhenermittlung vorhanden sind. Anders als auf der
  /// Tacho-Seite wird bei fehlender Berechtigung KEIN blockierender
  /// Hinweisbildschirm angezeigt - die Höhe ist eine Zusatzinformation,
  /// der Kompass selbst funktioniert auch ohne Standortzugriff.
  Future<bool> hasPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Stream<AltitudeReading> altitudeStream() {
    _controller ??= StreamController<AltitudeReading>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    return _controller!.stream;
  }

  void _startListening() {
    _subscription = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
      (position) {
        final accuracy =
            position.altitudeAccuracy.isFinite && position.altitudeAccuracy >= 0
                ? position.altitudeAccuracy
                : null;
        // Horizontale Positionsgenauigkeit (bezieht sich auf lat/lng, NICHT
        // auf die Höhe) - für die Genauigkeitsanzeige unterhalb der
        // DMS-Position auf der Kompass-Seite.
        final positionAccuracy =
            position.accuracy.isFinite && position.accuracy >= 0
                ? position.accuracy
                : null;
        _controller?.add(AltitudeReading(
          altitudeMeters: position.altitude,
          altitudeAccuracyMeters: accuracy,
          latitude: position.latitude,
          longitude: position.longitude,
          positionAccuracyMeters: positionAccuracy,
          timestamp: position.timestamp,
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
  }
}
