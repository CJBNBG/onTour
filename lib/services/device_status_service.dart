import 'dart:async';

import 'package:flutter/foundation.dart';

import 'motion_service.dart';
import 'satellite_service.dart';

/// Gemeinsamer Gerätestatus für den Statusbereich unter der App-Leiste
/// (siehe AppStatusBar): Anzahl der Satelliten im Fix sowie der
/// Stillstandszustand. Wird einmalig in HomeShell gehalten und läuft
/// dadurch über alle Seiten hinweg.
///
/// STILLSTAND: Grundlage ist der Beschleunigungssensor ([sensorStationary]).
/// Die Tacho-Seite kennt zusätzlich die GPS-Bedingung (unter 8 km/h) und
/// meldet ihren kombinierten, strengeren Zustand über
/// [reportSpeedPageStationary] zurück - solange sie sichtbar ist, hat
/// dieser Wert Vorrang ([displayStationary]).
///
/// SATELLITEN: Android liefert die Anzahl nur, solange GNSS aktiv ist.
/// Ältere Werte als [_satelliteStaleAfter] gelten als nicht aktuell
/// ([satellitesFresh]). Fehlt die Standort-Berechtigung beim App-Start,
/// scheitert das Abonnieren - solange noch nie ein Wert eintraf, wird
/// deshalb regelmäßig neu versucht.
class DeviceStatusService extends ChangeNotifier {
  static const Duration _satelliteStaleAfter = Duration(seconds: 15);
  static const Duration _maintenanceInterval = Duration(seconds: 5);

  final MotionService _motionService = MotionService();
  SatelliteService _satelliteService = SatelliteService();
  StreamSubscription<int>? _satelliteSubscription;
  StreamSubscription<bool>? _motionSubscription;
  Timer? _maintenanceTimer;
  bool _disposed = false;

  int? _satelliteCount;
  DateTime? _satelliteUpdatedAt;
  bool _satellitesFresh = false;

  bool? _sensorStationary;
  bool? _reportedStationary;

  /// Zuletzt gemeldete Satellitenanzahl im Fix (null = noch nie ein Wert).
  int? get satelliteCount => _satelliteCount;

  /// false, wenn noch kein Wert vorliegt oder der letzte zu alt ist.
  bool get satellitesFresh => _satellitesFresh;

  /// Reiner Sensorzustand (null = noch keine Messung/kein Sensor).
  bool? get sensorStationary => _sensorStationary;

  /// Anzuzeigender Stillstandszustand: der kombinierte Wert der Tacho-Seite,
  /// solange sie ihn meldet, sonst der Sensorzustand.
  bool? get displayStationary => _reportedStationary ?? _sensorStationary;

  void start() {
    _motionSubscription = _motionService.isStationaryStream().listen((value) {
      if (value == _sensorStationary) return;
      _sensorStationary = value;
      _notify();
    });
    _subscribeSatellites();
    _maintenanceTimer = Timer.periodic(_maintenanceInterval, (_) => _maintain());
  }

  void _subscribeSatellites() {
    _satelliteSubscription?.cancel();
    // Neue Instanz, da SatelliteService seinen Stream zwischenspeichert -
    // ein fehlgeschlagener Stream (z. B. mangels Berechtigung) wäre sonst
    // dauerhaft unbrauchbar.
    _satelliteService = SatelliteService();
    _satelliteSubscription = _satelliteService.satelliteCountStream().listen(
      (count) {
        _satelliteCount = count;
        _satelliteUpdatedAt = DateTime.now();
        _satellitesFresh = true;
        _notify();
      },
      onError: (Object error) {},
      cancelOnError: false,
    );
  }

  void _maintain() {
    final updatedAt = _satelliteUpdatedAt;
    if (updatedAt == null) {
      // Noch nie ein Wert (z. B. Berechtigung beim Start noch nicht erteilt).
      _subscribeSatellites();
      return;
    }
    final fresh = DateTime.now().difference(updatedAt) < _satelliteStaleAfter;
    if (fresh != _satellitesFresh) {
      _satellitesFresh = fresh;
      _notify();
    }
  }

  /// Von der Tacho-Seite aufgerufen: ihr kombinierter Stillstandszustand
  /// (Sensor UND GPS-Rohwert < 8 km/h) bzw. null, wenn sie ihn nicht (mehr)
  /// kennt (Seite verlassen, noch keine Messung).
  void reportSpeedPageStationary(bool? value) {
    if (value == _reportedStationary) return;
    _reportedStationary = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _maintenanceTimer?.cancel();
    _satelliteSubscription?.cancel();
    _motionSubscription?.cancel();
    _motionService.dispose();
    super.dispose();
  }
}
