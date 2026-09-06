import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/speed_accuracy_mode.dart';
import '../models/speed_reading.dart';

/// Mögliche Zustände, die vor dem eigentlichen Empfang von
/// Geschwindigkeitsdaten auftreten können - die UI zeigt für jeden Zustand
/// eine passende Rückmeldung/Handlungsaufforderung an.
enum LocationAvailability {
  /// Prüfung läuft noch.
  checking,

  /// Standortdienst des Geräts (GPS/Netzwerk) ist komplett deaktiviert.
  serviceDisabled,

  /// Berechtigung wurde (noch) nicht erteilt bzw. abgelehnt.
  permissionDenied,

  /// Berechtigung wurde dauerhaft abgelehnt ("nicht mehr fragen") - kann
  /// nur noch über die App-Einstellungen des Betriebssystems geändert
  /// werden.
  permissionDeniedForever,

  /// Alles bereit, Positions-Stream kann/läuft.
  ready,
}

/// Ermittelt die aktuelle Geschwindigkeit des Geräts über GPS/Netzwerk
/// (Paket `geolocator`). Die Abwägung zwischen Aktualität/Genauigkeit und
/// Akkuverbrauch ist NICHT mehr fest einprogrammiert, sondern wird über
/// [SpeedAccuracyMode] vom Nutzer in den Einstellungen gewählt (siehe
/// SettingsPage) und beim Start des Streams (siehe [speedStream])
/// übergeben.
class SpeedService {
  StreamSubscription<Position>? _subscription;
  StreamController<SpeedReading>? _controller;

  /// Prüft Standortdienst und Berechtigung. Liefert den aktuellen
  /// [LocationAvailability]-Zustand, ohne bereits einen Stream zu starten.
  Future<LocationAvailability> checkAvailability() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationAvailability.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return LocationAvailability.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationAvailability.permissionDeniedForever;
    }
    return LocationAvailability.ready;
  }

  /// Startet (bzw. liefert bei erneutem Aufruf denselben) Stream mit
  /// Geschwindigkeits-Messungen, konfiguriert nach der übergebenen
  /// [mode]. Muss NUR aufgerufen werden, wenn [checkAvailability] zuvor
  /// `ready` ergeben hat.
  ///
  /// HINWEIS: [mode] wird nur beim allerersten Aufruf (d. h. beim
  /// tatsächlichen Start des zugrunde liegenden GPS-Streams) wirksam - ein
  /// späterer Aufruf mit geändertem [mode] auf DERSELBEN SpeedService-
  /// Instanz ändert die bereits laufende Messung nicht mehr. Das ist im
  /// Praxisbetrieb unproblematisch, da für jeden Aufruf der Tacho-Seite
  /// ohnehin eine frische SpeedService-Instanz erzeugt wird (siehe
  /// HomeShell) - eine in den Einstellungen geänderte Stufe greift somit
  /// automatisch beim nächsten Öffnen der Tacho-Seite.
  Stream<SpeedReading> speedStream(SpeedAccuracyMode mode) {
    _controller ??= StreamController<SpeedReading>.broadcast(
      onListen: () => _startListening(mode),
      onCancel: _stopListening,
    );
    return _controller!.stream;
  }

  void _startListening(SpeedAccuracyMode mode) {
    _subscription = Geolocator.getPositionStream(
      locationSettings: mode.toLocationSettings(),
    ).listen(
      (position) {
        // Vereinzelt liefern Standortanbieter bei sehr geringer Bewegung
        // knapp negative Geschwindigkeiten (Messrauschen) - fachlich gibt
        // es keine negative Geschwindigkeit, daher auf 0 begrenzt.
        final speed = position.speed < 0 ? 0.0 : position.speed;
        final speedAccuracy =
            position.speedAccuracy.isFinite && position.speedAccuracy >= 0
                ? position.speedAccuracy
                : null;

        _controller?.add(SpeedReading(
          speedMetersPerSecond: speed,
          speedAccuracyMetersPerSecond: speedAccuracy,
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

  /// Muss aufgerufen werden, wenn die Geschwindigkeitsanzeige endgültig
  /// nicht mehr benötigt wird (z. B. beim Verlassen der Seite), damit der
  /// GPS-Empfang zuverlässig gestoppt wird.
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller?.close();
    _subscription = null;
    _controller = null;
  }
}
