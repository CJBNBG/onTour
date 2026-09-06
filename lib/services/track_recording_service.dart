import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/recorded_track.dart';
import '../models/track_point.dart';

/// Zustände, die eine Track-Aufzeichnung durchlaufen kann.
enum RecordingState {
  /// Keine Aufzeichnung aktiv, keine gesammelten Punkte.
  idle,

  /// Aufzeichnung läuft, GPS-Punkte werden gesammelt.
  recording,

  /// Aufzeichnung ist unterbrochen (gesammelte Punkte bleiben erhalten,
  /// es kommen aber keine neuen hinzu und die Dauer läuft nicht weiter) -
  /// z. B. für eine Rast unterwegs.
  paused,
}

/// Mögliche Zustände VOR dem eigentlichen Start der GPS-Erfassung - analog
/// zu LocationAvailability in speed_service.dart, hier als eigenes Enum,
/// da dieser Service unabhängig vom Tacho ist.
enum TrackLocationAvailability {
  checking,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  ready,
}

/// Zeichnet einen Track als fortlaufende Liste von [TrackPoint]s auf, über
/// einen eigenen, von den übrigen Standort-Streams (Tacho, Höhe)
/// unabhängigen GPS-Stream.
///
/// WICHTIG (bewusste Architektur-Ausnahme): Anders als die übrigen Services
/// dieses Projekts wird diese Instanz NICHT frisch pro Aufruf der
/// zugehörigen Seite erzeugt, sondern einmalig in HomeShell gehalten und an
/// TrackPage durchgereicht (siehe dortiger Kommentar sowie HomeShell). Eine
/// laufende Aufzeichnung soll schließlich WEITERLAUFEN, auch wenn
/// zwischenzeitlich z. B. die Kompass-Seite betrachtet wird - das
/// widerspricht bewusst dem sonst in diesem Projekt üblichen "frischer
/// Service pro Seitenaufruf, disposed beim Verlassen"-Muster, ist hier aber
/// fachlich zwingend nötig, da ein Abbruch der GPS-Aufzeichnung beim
/// Wechsel auf einen anderen Tab fatal für den eigentlichen Zweck der Seite
/// wäre.
class TrackRecordingService {
  StreamSubscription<Position>? _subscription;
  final List<TrackPoint> _points = [];
  final StreamController<void> _updatesController =
      StreamController<void>.broadcast();

  RecordingState _state = RecordingState.idle;
  DateTime? _startTime;
  double _distanceMeters = 0;

  /// Aufsummierte Dauer aller bisherigen Pausen dieser Aufzeichnung - wird
  /// von [elapsed] abgezogen, damit Pausen nicht in die angezeigte
  /// Aufzeichnungsdauer einfließen.
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartedAt;

  /// Aktuelle Aufzeichnungspunkte (schreibgeschützte Sicht).
  List<TrackPoint> get points => List.unmodifiable(_points);

  RecordingState get state => _state;
  double get distanceMeters => _distanceMeters;
  DateTime? get startTime => _startTime;

  /// Tatsächliche Aufzeichnungsdauer, Pausen bereits herausgerechnet.
  Duration get elapsed {
    final start = _startTime;
    if (start == null) return Duration.zero;
    final end = _state == RecordingState.paused && _pauseStartedAt != null
        ? _pauseStartedAt!
        : DateTime.now();
    final raw = end.difference(start) - _pausedDuration;
    return raw.isNegative ? Duration.zero : raw;
  }

  /// Feuert bei jeder relevanten Änderung (neuer Punkt, Zustandswechsel) -
  /// die TrackPage nutzt das für ihr setState, ohne dass diese Klasse
  /// selbst von Flutter/ChangeNotifier abhängen muss.
  Stream<void> get updates => _updatesController.stream;

  Future<TrackLocationAvailability> checkAvailability() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return TrackLocationAvailability.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return TrackLocationAvailability.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return TrackLocationAvailability.permissionDeniedForever;
    }
    return TrackLocationAvailability.ready;
  }

  /// Startet eine neue Aufzeichnung. Darf nur aufgerufen werden, wenn der
  /// Zustand vorher [RecordingState.idle] war (die TrackPage stellt das
  /// über den Button-Zustand sicher).
  void start() {
    _points.clear();
    _distanceMeters = 0;
    _pausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _startTime = DateTime.now();
    _state = RecordingState.recording;
    _updatesController.add(null);
    _startListening();
  }

  void _startListening() {
    _subscription ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        // Kleiner distanceFilter als bei der frueheren Kartenseite (dort
        // 5 m), da fuer eine moeglichst genaue Streckenlinie auch kleine
        // Bewegungen erfasst werden sollen - Genauigkeit hat hier bewusst
        // Vorrang vor Akkuverbrauch.
        distanceFilter: 3,
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (_state != RecordingState.recording) return;
    final point = TrackPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeMeters: position.altitude.isFinite ? position.altitude : null,
      timestamp: position.timestamp,
    );
    if (_points.isNotEmpty) {
      final last = _points.last;
      _distanceMeters += Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        point.latitude,
        point.longitude,
      );
    }
    _points.add(point);
    _updatesController.add(null);
  }

  /// Unterbricht die Aufzeichnung (GPS-Stream wird gestoppt, gesammelte
  /// Punkte bleiben erhalten) - z. B. für eine Rast unterwegs.
  Future<void> pause() async {
    if (_state != RecordingState.recording) return;
    await _subscription?.cancel();
    _subscription = null;
    _pauseStartedAt = DateTime.now();
    _state = RecordingState.paused;
    _updatesController.add(null);
  }

  /// Setzt eine unterbrochene Aufzeichnung fort.
  void resume() {
    if (_state != RecordingState.paused) return;
    final pauseStart = _pauseStartedAt;
    if (pauseStart != null) {
      _pausedDuration += DateTime.now().difference(pauseStart);
      _pauseStartedAt = null;
    }
    _state = RecordingState.recording;
    _updatesController.add(null);
    _startListening();
  }

  /// Beendet die Aufzeichnung endgültig und liefert das Ergebnis als
  /// [RecordedTrack] - null, falls weniger als zwei Punkte gesammelt
  /// wurden (z. B. bei sofortigem Abbruch), da ein Track mit nur einem
  /// Punkt fachlich keinen Sinn ergibt.
  Future<RecordedTrack?> stop({required String name}) async {
    await _subscription?.cancel();
    _subscription = null;
    final wasActive = _state != RecordingState.idle;
    final recordedElapsed = elapsed;
    final start = _startTime;
    _state = RecordingState.idle;
    _updatesController.add(null);

    if (!wasActive || _points.length < 2 || start == null) {
      return null;
    }

    return RecordedTrack(
      id: start.millisecondsSinceEpoch.toString(),
      name: name,
      startTime: start,
      endTime: DateTime.now(),
      points: List.of(_points),
      distanceMeters: _distanceMeters,
      recordedDuration: recordedElapsed,
    );
  }

  /// Bricht eine laufende/unterbrochene Aufzeichnung ab, OHNE ein Ergebnis
  /// zu liefern - die gesammelten Punkte werden verworfen.
  Future<void> discard() async {
    await _subscription?.cancel();
    _subscription = null;
    _points.clear();
    _distanceMeters = 0;
    _pausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _startTime = null;
    _state = RecordingState.idle;
    _updatesController.add(null);
  }

  /// Muss aufgerufen werden, wenn die App komplett beendet wird (siehe
  /// HomeShell.dispose) - NICHT beim einfachen Verlassen der Track-Seite,
  /// da eine laufende Aufzeichnung ja gerade dann weiterlaufen soll.
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _updatesController.close();
  }
}
