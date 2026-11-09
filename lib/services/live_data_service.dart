import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/altitude_reading.dart';
import '../models/compass_reading.dart';
import '../models/pressure_reading.dart';
import '../models/speed_accuracy_mode.dart';
import '../models/user_profile.dart';
import 'altitude_correction.dart';
import 'barometer_altitude_service.dart';
import 'compass_service.dart';
import 'device_status_service.dart';
import 'pressure_trend_service.dart';

/// Zustand der Standortfreigabe für die Start-Seite.
enum LiveLocationState {
  checking,
  ready,
  serviceDisabled,
  denied,
  deniedForever,
}

/// Gemeinsame Datenquelle der Start-Seite (siehe README Abschnitt 56).
///
/// Abonniert AUSSCHLIESSLICH die Sensoren, die die gerade belegten Slots
/// tatsächlich brauchen ([setRequirements]) - eine Start-Seite mit
/// Tempo, Höhe, Kurs, Kompass und Position würde sonst GPS, Barometer,
/// Magnetometer und Gyroskop gleichzeitig laufen lassen. Wird die Seite
/// verlassen, wird der Service disposed und alle Sensoren stoppen (wie bei
/// den übrigen Seiten, siehe HomeShell).
///
/// Bewusst EIN GPS-Stream für Tempo, Kurs, Höhe und Position (kein
/// Stream je Slot). Der Luftdruck kommt dagegen aus dem ohnehin
/// dauerhaft laufenden [PressureTrendService] aus HomeShell, der Kompass
/// aus einer eigenen [CompassService]-Instanz nur bei belegtem
/// Kompass-Slot.
class LiveDataService extends ChangeNotifier {
  /// Unterhalb dieser GPS-Rohgeschwindigkeit (km/h) wird ein vom
  /// Bewegungssensor bestätigter Stillstand als "echte Null" gewertet -
  /// dieselbe Regel wie auf der Tacho-Seite (siehe SpeedPage).
  static const double _stationaryOverrideThresholdKmh = 8.0;

  /// Unterhalb dieser Geschwindigkeit ist der GPS-Kurs unzuverlässig.
  static const double _minSpeedForCourseMs = 1.0;

  /// Ältere GPS-Werte gelten für den Kurs als veraltet (im Stand kommen
  /// wegen des distanceFilters keine neuen Punkte mehr).
  static const Duration _courseMaxAge = Duration(seconds: 5);

  /// GPS-Höhen mit schlechterer Genauigkeit (Meter) werden - falls kein
  /// Barometer vorhanden ist - nicht angezeigt (wie in der
  /// Track-Aufzeichnung).
  static const double _maxUsableGpsAltitudeAccuracyMeters = 25;

  static const double _declinationRefreshDegrees = 0.25;

  final DeviceStatusService status;
  final PressureTrendService pressureService;
  final SpeedAccuracyMode accuracyMode;

  LiveDataService({
    required this.status,
    required this.pressureService,
    required this.accuracyMode,
  }) {
    status.addListener(_scheduleNotify);
  }

  bool _disposed = false;
  Timer? _notifyTimer;
  Timer? _tickTimer;

  // ==== Anforderungen (aus den belegten Slots) ====
  bool _needsGps = false;
  bool _needsBarometer = false;
  bool _needsCompass = false;
  bool _needsPressure = false;

  // ==== GPS ====
  StreamSubscription<Position>? _gpsSubscription;
  bool _gpsStarting = false;
  LiveLocationState _locationState = LiveLocationState.checking;
  double? _rawSpeedMs;
  double? _speedAccuracyMs;
  double? _heading;
  DateTime? _lastGpsAt;
  double? _latitude;
  double? _longitude;
  double? _positionAccuracyMeters;
  double? _declinationLat;
  double? _declinationLon;

  // ==== Höhe ====
  BarometerAltitudeService? _barometer;
  StreamSubscription<AltitudeReading>? _barometerSubscription;
  double? _altitudeMeters;
  bool _altitudeFromBarometer = false;
  bool _barometerUnavailable = false;
  bool _hasGpsAltitude = false;

  // ==== Kompass ====
  CompassService? _compass;
  StreamSubscription<CompassReading>? _compassSubscription;
  bool _compassSupported = true;
  bool _compassDisturbed = false;

  /// Aktuelle Peilung für die Kompassrose - bewusst ein eigener
  /// [ValueNotifier], da der Kompass bis zu 20x pro Sekunde meldet und
  /// nur die Rose (nicht die ganze Seite) neu gezeichnet werden soll.
  final ValueNotifier<double?> compassHeading = ValueNotifier<double?>(null);

  // ==== Luftdruck ====
  StreamSubscription<void>? _pressureSubscription;

  // ==== Öffentliche Sicht ====

  LiveLocationState get locationState => _locationState;

  /// Tempo in m/s mit Stillstandskorrektur - null ohne GPS-Messung.
  double? get speedMs {
    final raw = _rawSpeedMs;
    if (raw == null) return null;
    final rawKmh = raw * 3.6;
    if (status.sensorStationary == true && rawKmh < _stationaryOverrideThresholdKmh) {
      return 0.0;
    }
    return raw;
  }

  double? get speedAccuracyMs => _speedAccuracyMs;

  /// Stillstand (true) bzw. Bewegung (false) für das Symbol der
  /// Tempo-Kachel - dieselbe Regel wie auf der Tacho-Seite (Bewegungssensor
  /// UND GPS-Rohwert unter 8 km/h). Ohne GPS-Messung nur der Sensorzustand,
  /// null = unbekannt.
  bool? get stationary {
    final raw = _rawSpeedMs;
    if (raw == null) return status.sensorStationary;
    return status.sensorStationary == true && raw * 3.6 < _stationaryOverrideThresholdKmh;
  }

  /// Kurs über Grund (GPS, 0-360°) - null bei Stillstand/Schritttempo
  /// oder veralteter Messung.
  double? get courseDegrees {
    final at = _lastGpsAt;
    final speed = _rawSpeedMs;
    final heading = _heading;
    if (at == null || speed == null || heading == null) return null;
    if (DateTime.now().difference(at) > _courseMaxAge) return null;
    if (speed < _minSpeedForCourseMs) return null;
    return heading;
  }

  double? get altitudeMeters => _altitudeMeters;
  bool get altitudeFromBarometer => _altitudeFromBarometer;

  /// true, solange noch keine brauchbare Höhe vorliegt, obwohl GPS-Höhen
  /// schon eintreffen (Barometer wird noch gegen GPS kalibriert).
  bool get altitudePending =>
      _altitudeMeters == null && _hasGpsAltitude && !_barometerUnavailable;

  double? get latitude => _latitude;
  double? get longitude => _longitude;
  double? get positionAccuracyMeters => _positionAccuracyMeters;

  PressureReading? get pressure => pressureService.current;

  bool get compassSupported => _compassSupported;
  bool get compassDisturbed => _compassDisturbed;

  // ==== Steuerung ====

  /// Legt fest, welche Sensoren laufen müssen. Darf jederzeit (auch
  /// mehrfach) aufgerufen werden, z. B. bei Profilwechsel - nicht
  /// mehr benötigte Sensoren werden gestoppt.
  void setRequirements(Set<SlotType> slots) {
    if (_disposed) return;
    _needsGps = slots.any((s) =>
        s == SlotType.speed ||
        s == SlotType.course ||
        s == SlotType.altitude ||
        s == SlotType.position ||
        s == SlotType.compass);
    _needsBarometer = slots.contains(SlotType.altitude);
    _needsCompass = slots.contains(SlotType.compass);
    _needsPressure = slots.contains(SlotType.pressure);

    if (_needsGps) {
      unawaited(_startGps());
      _tickTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _scheduleNotify());
    } else {
      _stopGps();
      _tickTimer?.cancel();
      _tickTimer = null;
    }

    if (_needsBarometer) {
      _startBarometer();
    } else {
      _stopBarometer();
    }

    if (_needsCompass) {
      _startCompass();
    } else {
      _stopCompass();
    }

    if (_needsPressure) {
      _pressureSubscription ??= pressureService.updates.listen((_) => _scheduleNotify());
    } else {
      _pressureSubscription?.cancel();
      _pressureSubscription = null;
    }
  }

  // ==== GPS ====

  Future<void> _startGps() async {
    if (_gpsSubscription != null || _gpsStarting) return;
    _gpsStarting = true;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (_disposed) return;
      if (!enabled) {
        _locationState = LiveLocationState.serviceDisabled;
        _scheduleNotify();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (_disposed) return;
      if (permission == LocationPermission.denied) {
        _locationState = LiveLocationState.denied;
        _scheduleNotify();
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _locationState = LiveLocationState.deniedForever;
        _scheduleNotify();
        return;
      }
      _locationState = LiveLocationState.ready;
      _scheduleNotify();
      // Anforderungen können sich während der Berechtigungsabfrage
      // geändert haben.
      if (!_needsGps) return;

      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: accuracyMode.toLocationSettings(),
      ).listen(
        _onPosition,
        onError: (Object error) {
          _locationState = LiveLocationState.serviceDisabled;
          _scheduleNotify();
        },
      );
    } finally {
      _gpsStarting = false;
    }
  }

  void _stopGps() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
  }

  void _onPosition(Position p) {
    _lastGpsAt = DateTime.now();
    _locationState = LiveLocationState.ready;

    _rawSpeedMs = p.speed.isFinite ? (p.speed < 0 ? 0.0 : p.speed) : null;
    _speedAccuracyMs = p.speedAccuracy.isFinite && p.speedAccuracy >= 0 ? p.speedAccuracy : null;
    _heading = p.heading.isFinite && p.heading >= 0 ? p.heading : null;

    _latitude = p.latitude;
    _longitude = p.longitude;
    _positionAccuracyMeters = p.accuracy.isFinite && p.accuracy >= 0 ? p.accuracy : null;

    _maybeUpdateDeclination(p.latitude, p.longitude, p.altitude);

    if (_needsBarometer && p.altitude.isFinite) {
      _hasGpsAltitude = true;
      final correction = AltitudeCorrection.instance;
      unawaited(correction.refreshIfDue(
        dartAltitude: p.altitude,
        shownAltitude: _altitudeMeters,
      ));
      final reference = correction.gpsReference(p.altitude);
      _barometer?.calibrate(
        referenceAltitudeMeters: reference,
        referenceLatitude: p.latitude,
        referenceLongitude: p.longitude,
        referencePositionAccuracyMeters: _positionAccuracyMeters,
        referenceAltitudeAccuracyMeters: p.altitudeAccuracy.isFinite ? p.altitudeAccuracy : null,
      );
      // Ohne Barometer: GPS-Höhe nur bei ausreichender Genauigkeit (0 =
      // keine Angabe des Systems, wird akzeptiert).
      if (_barometerUnavailable) {
        final accuracy = p.altitudeAccuracy;
        final usable = !accuracy.isFinite ||
            accuracy <= 0 ||
            accuracy <= _maxUsableGpsAltitudeAccuracyMeters;
        if (usable) {
          _altitudeMeters = correction.display(reference);
          pressureService.noteAltitude(_altitudeMeters!);
        }
      }
    }
    _scheduleNotify();
  }

  void _maybeUpdateDeclination(double lat, double lon, double altitude) {
    final compass = _compass;
    if (compass == null) return;
    final lastLat = _declinationLat;
    final lastLon = _declinationLon;
    final needsUpdate = lastLat == null ||
        lastLon == null ||
        (lat - lastLat).abs() > _declinationRefreshDegrees ||
        (lon - lastLon).abs() > _declinationRefreshDegrees;
    if (!needsUpdate) return;
    _declinationLat = lat;
    _declinationLon = lon;
    unawaited(compass.updateDeclination(
      latitude: lat,
      longitude: lon,
      altitude: altitude.isFinite ? altitude : 0,
    ));
  }

  // ==== Barometer / Höhe ====

  void _startBarometer() {
    if (_barometerSubscription != null) return;
    final service = BarometerAltitudeService();
    _barometer = service;
    _barometerUnavailable = false;
    _barometerSubscription = service.altitudeStream().listen(
      (reading) {
        _altitudeMeters = AltitudeCorrection.instance.display(reading.altitudeMeters);
        _altitudeFromBarometer = true;
        // Meldet die Höhe an den Luftdruck-Trend (Erkennung von
        // Höhenänderungen, siehe PressureTrendService) - wie die
        // Kompass-Seite.
        pressureService.noteAltitude(_altitudeMeters!);
        _scheduleNotify();
      },
      // Gerät ohne Barometer: es bleibt bei der (gefilterten) GPS-Höhe.
      onError: (Object error) {
        _barometerUnavailable = true;
        _altitudeFromBarometer = false;
        _scheduleNotify();
      },
    );
  }

  void _stopBarometer() {
    _barometerSubscription?.cancel();
    _barometerSubscription = null;
    final service = _barometer;
    _barometer = null;
    if (service != null) unawaited(service.dispose());
    _altitudeMeters = null;
    _altitudeFromBarometer = false;
    _barometerUnavailable = false;
    _hasGpsAltitude = false;
  }

  // ==== Kompass ====

  void _startCompass() {
    if (_compass != null) return;
    final service = CompassService();
    if (!service.isSupported) {
      _compassSupported = false;
      _scheduleNotify();
      return;
    }
    _compassSupported = true;
    _compass = service;
    _compassSubscription = service.readingStream().listen((reading) {
      compassHeading.value = reading.headingDegrees;
      if (reading.isDisturbed != _compassDisturbed) {
        _compassDisturbed = reading.isDisturbed;
        _scheduleNotify();
      }
    });
    // Position schon bekannt (Kompass-Slot erst später hinzugekommen)?
    final lat = _latitude;
    final lon = _longitude;
    if (lat != null && lon != null) {
      _maybeUpdateDeclination(lat, lon, 0);
    }
  }

  void _stopCompass() {
    _compassSubscription?.cancel();
    _compassSubscription = null;
    final service = _compass;
    _compass = null;
    if (service != null) unawaited(service.dispose());
    _declinationLat = null;
    _declinationLon = null;
    _compassDisturbed = false;
    compassHeading.value = null;
  }

  // ==== Benachrichtigung ====

  /// Fasst viele schnell aufeinanderfolgende Änderungen (Barometer,
  /// Statusbereich) zu höchstens einem Neuaufbau alle 200 ms zusammen.
  /// Löst NIE synchron aus - dadurch gefahrlos auch aus build()-nahen
  /// Aufrufen nutzbar.
  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 200), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    status.removeListener(_scheduleNotify);
    _notifyTimer?.cancel();
    _tickTimer?.cancel();
    _stopGps();
    _stopBarometer();
    _stopCompass();
    _pressureSubscription?.cancel();
    compassHeading.dispose();
    super.dispose();
  }
}
