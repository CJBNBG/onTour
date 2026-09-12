import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/recorded_track.dart';
import '../models/track_point.dart';
import 'motion_service.dart';

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
///
/// NEU - Automatische Pause bei Stillstand: Nutzt intern denselben
/// beschleunigungssensor-basierten [MotionService] wie die Tacho-Seite
/// (siehe README Abschnitt 6), hier aber mit einer anderen Konsequenz -
/// statt nur die Geschwindigkeitsanzeige auf 0 zu korrigieren, wird die
/// Aufzeichnung selbst automatisch pausiert, solange Stillstand erkannt
/// wird (z. B. an einer Ampel oder während einer kurzen Rast), und
/// automatisch fortgesetzt, sobald wieder Bewegung erkannt wird. WICHTIGER
/// Unterschied zur manuellen Pause (Button in TrackPage): [_autoPaused]
/// merkt sich, OB die aktuelle Pause automatisch (durch Stillstand) oder
/// manuell ausgelöst wurde - nur eine automatische Pause wird bei
/// erneuter Bewegung auch automatisch wieder aufgehoben; eine manuelle
/// Pause bleibt bestehen, bis der Nutzer selbst "Fortsetzen" antippt
/// (siehe [_onStationaryChanged]).
///
/// NEU - Aufzeichnung im Hintergrund: Der GPS-Stream läuft seit einer
/// späteren Erweiterung als nativer Android-Foreground-Service mit
/// dauerhafter Benachrichtigung (siehe [_startListening],
/// `ForegroundNotificationConfig`) - dadurch bricht die Aufzeichnung
/// NICHT mehr ab, wenn die App in den Hintergrund wechselt (z. B. weil
/// währenddessen kurz eine andere App wie Google Maps zur Navigation
/// geöffnet wird). Betroffen ist ausschließlich der GPS-Stream während
/// `RecordingState.recording` - während einer Pause (automatisch oder
/// manuell) wird der Stream wie bisher komplett beendet, wodurch auch
/// die Benachrichtigung verschwindet (bewusst so, siehe [_pauseInternal]
/// - spart während einer Pause Akku).
class TrackRecordingService {
  StreamSubscription<Position>? _subscription;
  final List<TrackPoint> _points = [];
  final StreamController<void> _updatesController =
      StreamController<void>.broadcast();

  final MotionService _motionService = MotionService();
  StreamSubscription<bool>? _motionSubscription;

  RecordingState _state = RecordingState.idle;
  DateTime? _startTime;
  double _distanceMeters = 0;

  /// Aufsummierte Dauer aller bisherigen Pausen dieser Aufzeichnung - wird
  /// von [elapsed] abgezogen, damit Pausen nicht in die angezeigte
  /// Aufzeichnungsdauer einfließen.
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartedAt;

  /// true, solange die aktuelle Pause automatisch durch erkannten
  /// Stillstand ausgelöst wurde (statt durch den "Pause"-Button in
  /// TrackPage) - siehe Klassenkommentar.
  bool _autoPaused = false;

  /// Dauer der "Schonfrist" nach einem MANUELLEN Fortsetzen (Button), in
  /// der die automatische Stillstands-Pause bewusst ausgesetzt ist -
  /// siehe [resume] und [_onStationaryChanged]. Verhindert, dass ein
  /// manuelles Fortsetzen sofort wieder von der automatischen Erkennung
  /// rückgängig gemacht wird, wenn das Fahrzeug im Moment des Antippens
  /// noch nicht tatsächlich losgefahren ist.
  static const _manualResumeGracePeriod = Duration(seconds: 10);
  DateTime? _manualResumeGraceUntil;

  /// Aktuelle Aufzeichnungspunkte (schreibgeschützte Sicht).
  List<TrackPoint> get points => List.unmodifiable(_points);

  RecordingState get state => _state;
  double get distanceMeters => _distanceMeters;
  DateTime? get startTime => _startTime;

  /// true, solange [state] == paused UND diese Pause automatisch durch
  /// erkannten Stillstand ausgelöst wurde - TrackPage nutzt das für einen
  /// erklärenden Hinweistext (siehe dort).
  bool get isAutoPaused => _autoPaused;

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
    _autoPaused = false;
    _manualResumeGraceUntil = null;
    _startTime = DateTime.now();
    _state = RecordingState.recording;
    _updatesController.add(null);
    _startListening();
    _startMotionListening();
  }

  /// Startet - sofern noch nicht geschehen - das Beobachten des
  /// Bewegungssensors für die automatische Stillstands-Pause (siehe
  /// Klassenkommentar). Läuft bewusst unabhängig vom GPS-Stream weiter,
  /// auch während einer Pause, damit ein Wiederanfahren nach einer
  /// automatischen Pause zuverlässig erkannt wird.
  void _startMotionListening() {
    _motionSubscription ??=
        _motionService.isStationaryStream().listen(_onStationaryChanged);
  }

  Future<void> _stopMotionListening() async {
    await _motionSubscription?.cancel();
    _motionSubscription = null;
    await _motionService.dispose();
  }

  void _onStationaryChanged(bool stationary) {
    if (stationary && _state == RecordingState.recording) {
      // Innerhalb der Schonfrist nach einem manuellen Fortsetzen wird die
      // automatische Pause bewusst ausgesetzt (siehe
      // _manualResumeGraceUntil) - verhindert ein sofortiges erneutes
      // automatisches Pausieren, solange das Fahrzeug gerade erst wieder
      // losfährt.
      final graceUntil = _manualResumeGraceUntil;
      if (graceUntil != null && DateTime.now().isBefore(graceUntil)) return;

      // Stillstand waehrend aktiver Aufzeichnung erkannt - automatisch
      // pausieren (gesammelte Punkte bleiben erhalten, siehe
      // _pauseInternal).
      _autoPaused = true;
      _pauseInternal();
    } else if (!stationary && _state == RecordingState.paused && _autoPaused) {
      // Bewegung wieder erkannt UND die aktuelle Pause war automatisch
      // ausgeloest (nicht manuell) - automatisch fortsetzen.
      resume(manual: false);
    }
  }

  void _startListening() {
    _subscription ??= Geolocator.getPositionStream(
      // AndroidSettings statt der bisherigen plattformneutralen
      // LocationSettings - beide Klassen kommen aus demselben Paket
      // `geolocator` (das die Android-spezifische Klasse aus
      // `geolocator_android` für Android bequem mit re-exportiert), ein
      // zusätzlicher pubspec-Eintrag ist dafür nicht nötig. Passend dazu,
      // dass diese App bewusst ausschließlich auf Android läuft (siehe
      // README), ist das hier unbedingt.
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        // Kleiner distanceFilter als bei der frueheren Kartenseite (dort
        // 5 m), da fuer eine moeglichst genaue Streckenlinie auch kleine
        // Bewegungen erfasst werden sollen - Genauigkeit hat hier bewusst
        // Vorrang vor Akkuverbrauch.
        distanceFilter: 3,
        // NEU - Hintergrund-Aufzeichnung: Ist foregroundNotificationConfig
        // gesetzt, startet geolocator die Standortabfrage als nativen
        // Android-Foreground-Service mit dauerhafter Benachrichtigung.
        // Dadurch läuft die GPS-Erfassung zuverlässig weiter, auch wenn
        // onTour in den Hintergrund wechselt (z. B. weil währenddessen
        // eine andere Navigations-App wie Google Maps geöffnet wird) -
        // ohne das würde Android die App als Hintergrundprozess
        // behandeln und die Standortabfrage nach kurzer Zeit drosseln
        // bzw. beenden (siehe README Abschnitt 19). Die Benachrichtigung
        // ist absichtlich fest verankert (setOngoing: true), damit sie
        // nicht versehentlich weggewischt und die Aufzeichnung dadurch
        // beendet wird.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'onTour zeichnet auf',
          notificationText: 'Track-Aufzeichnung läuft im Hintergrund weiter',
          // Verweist auf dasselbe App-Icon, das auch als Launcher-Icon
          // dient (siehe pubspec.yaml, flutter_launcher_icons: android:
          // "launcher_icon") - der Ressourcenname muss exakt
          // übereinstimmen, sonst schlägt das Laden des Icons fehl.
          notificationIcon: AndroidResource(name: 'launcher_icon', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
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

  /// Manuelles Pausieren über den "Pause"-Button in TrackPage.
  ///
  /// WICHTIG: Funktioniert auch dann, wenn die Aufzeichnung bereits
  /// AUTOMATISCH pausiert ist (state == paused, [_autoPaused] == true) -
  /// in diesem Fall wird die bestehende Pause lediglich als manuell
  /// markiert (`_autoPaused = false`), damit sie NICHT mehr automatisch
  /// bei erkannter Bewegung aufgehoben wird, sondern nur noch über einen
  /// expliziten Tap auf "Fortsetzen". Frühere Fehlerursache: Ohne diese
  /// Sonderbehandlung hatte ein Antippen von "Pause" während einer schon
  /// laufenden automatischen Pause GAR KEINE Wirkung (die Funktion brach
  /// sofort ab, da der Zustand bereits "paused" statt "recording" war) -
  /// dadurch blieb die Pause intern fälschlich als "automatisch"
  /// markiert und wurde beim nächsten Aufnehmen des Telefons (das der
  /// Bewegungssensor bereits als Bewegung wertete) ungewollt sofort
  /// wieder automatisch aufgehoben, noch bevor der Nutzer selbst
  /// "Fortsetzen" antippen konnte.
  Future<void> pause() async {
    if (_state == RecordingState.paused) {
      // Bereits pausiert (automatisch ODER manuell) - Tap bestaetigt/
      // "verfestigt" die Pause als manuell, egal wie sie ursprünglich
      // zustande kam.
      _autoPaused = false;
      _updatesController.add(null);
      return;
    }
    if (_state != RecordingState.recording) return;
    _autoPaused = false;
    await _pauseInternal();
  }

  /// Gemeinsame Pause-Logik für manuelles UND automatisches Pausieren -
  /// stoppt nur den GPS-Stream (der Bewegungssensor bleibt aktiv, siehe
  /// _startMotionListening), gesammelte Punkte bleiben erhalten.
  Future<void> _pauseInternal() async {
    if (_state != RecordingState.recording) return;
    await _subscription?.cancel();
    _subscription = null;
    _pauseStartedAt = DateTime.now();
    _state = RecordingState.paused;
    _updatesController.add(null);
  }

  /// Setzt eine unterbrochene Aufzeichnung fort.
  ///
  /// [manual] ist `true` bei einem Antippen des "Fortsetzen"-Buttons in
  /// TrackPage (Standardwert - der Aufrufer muss dafür nichts angeben)
  /// und `false`, wenn der Aufruf automatisch durch erkannte Bewegung
  /// nach einer Stillstands-Pause erfolgt (siehe [_onStationaryChanged]).
  /// Nach einem MANUELLEN Fortsetzen wird die automatische
  /// Stillstands-Erkennung für [_manualResumeGracePeriod] ausgesetzt
  /// (siehe [_manualResumeGraceUntil]) - so kann der Nutzer die
  /// Aufzeichnung zuverlässig fortsetzen, auch wenn das Fahrzeug im
  /// Moment des Antippens noch nicht tatsächlich losgefahren ist.
  void resume({bool manual = true}) {
    if (_state != RecordingState.paused) return;
    final pauseStart = _pauseStartedAt;
    if (pauseStart != null) {
      _pausedDuration += DateTime.now().difference(pauseStart);
      _pauseStartedAt = null;
    }
    _autoPaused = false;
    if (manual) {
      _manualResumeGraceUntil = DateTime.now().add(_manualResumeGracePeriod);
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
    await _stopMotionListening();
    final wasActive = _state != RecordingState.idle;
    final recordedElapsed = elapsed;
    final start = _startTime;
    _autoPaused = false;
    _manualResumeGraceUntil = null;
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
    await _stopMotionListening();
    _points.clear();
    _distanceMeters = 0;
    _pausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _autoPaused = false;
    _manualResumeGraceUntil = null;
    _startTime = null;
    _state = RecordingState.idle;
    _updatesController.add(null);
  }

  /// Muss aufgerufen werden, wenn die App komplett beendet wird (siehe
  /// HomeShell.dispose) - NICHT beim einfachen Verlassen der Track-Seite,
  /// da eine laufende Aufzeichnung ja gerade dann weiterlaufen soll.
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _stopMotionListening();
    await _updatesController.close();
  }
}
