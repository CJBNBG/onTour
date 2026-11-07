import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../models/altitude_reading.dart';
import '../models/recorded_track.dart';
import '../models/track_point.dart';
import 'altitude_correction.dart';
import 'barometer_altitude_service.dart';
import 'diagnostic_log_service.dart';
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
  /// NEU (siehe README Abschnitt 37): Öffentlich, damit die
  /// Genauigkeits-Anzeige auf der Track-Seite (`AccuracyBadge`) die hier
  /// tatsächlich fest verwendete Genauigkeit anzeigen kann, ohne sie ein
  /// zweites Mal (und damit potenziell abweichend) zu duplizieren -
  /// siehe [_startListening].
  static const LocationAccuracy fixedAccuracy = LocationAccuracy.best;

  /// NEU (siehe README Abschnitt 38): Mindestabstand zwischen dem
  /// Beenden einer Aufzeichnung und dem tatsächlichen (Re-)Start des
  /// Positions-Streams einer NEUEN Aufzeichnung, siehe [start]. GRUND:
  /// Ein wiederholt beobachtetes, für den Nutzer nicht erkennbares
  /// Ausbleiben des sichtbaren Foreground-Service (siehe README für die
  /// ausführliche Herleitung) deckt sich mit einem in den geolocator-
  /// eigenen GitHub-Diskussionen dokumentierten Verhalten: Das Plugin
  /// führt intern Buch darüber, ob "noch eine FlutterEngine verbunden
  /// ist", bevor es den nativen Standort-Service tatsächlich stoppt -
  /// bei unserer bewusst PERSISTENTEN Engine (Abschnitt 21), die
  /// wiederholt an neue Activity-Instanzen angehängt wird, kann diese
  /// interne Buchführung vermutlich durcheinandergeraten, sodass der
  /// vorherige Service beim sofortigen Start einer neuen Aufzeichnung
  /// noch nicht vollständig abgebaut ist. Diese kurze Wartezeit gibt dem
  /// Plugin Zeit, den Abbau abzuschließen, bevor ein neuer Service
  /// angefordert wird - eine pragmatische Gegenmaßnahme für eine
  /// vermutete, nicht abschließend bewiesene Race Condition (siehe
  /// README für die Einschränkung dieser Diagnose).
  static const Duration _minRestartGap = Duration(milliseconds: 800);

  /// Zeitpunkt, zu dem die zuletzt laufende Aufzeichnung beendet wurde
  /// (siehe [stop]/[discard]) - Grundlage für [_minRestartGap]. null vor
  /// der allerersten Aufzeichnung dieser Service-Instanz.
  DateTime? _lastStoppedAt;

  /// NEU (siehe README Abschnitt 22): Kanal zu der nativen Planung/
  /// Stornierung einer Erinnerungs-Benachrichtigung für eine anhaltend
  /// pausierte Aufzeichnung (AutoPauseReminderScheduler.kt). Bewusst
  /// nativ über `AlarmManager` statt über einen Dart-`Timer` umgesetzt:
  /// Ein Dart-Timer würde sterben, sobald der Android-Prozess ohne
  /// laufenden Foreground-Service (der während einer Pause bewusst
  /// beendet wird, siehe _pauseInternal/Abschnitt 19) im Hintergrund
  /// beendet wird - ein `AlarmManager`-Alarm übersteht das dagegen, da er
  /// systemseitig verwaltet wird, unabhängig vom App-Prozess.
  static const MethodChannel _reminderChannel =
      MethodChannel('ontour/auto_pause_reminder');

  StreamSubscription<Position>? _subscription;
  final List<TrackPoint> _points = [];
  final StreamController<void> _updatesController =
      StreamController<void>.broadcast();

  final MotionService _motionService = MotionService();
  StreamSubscription<bool>? _motionSubscription;

  /// NEU (siehe README Abschnitt 27): Liefert - analog zur Kompass-Seite,
  /// siehe Abschnitt 10 - eine deutlich präzisere, gegen die eigene
  /// GPS-Höhe kalibrierte Höhe. Wird für jeden aufgezeichneten
  /// [TrackPoint] bevorzugt gegenüber der GPS-Rohhöhe verwendet, sobald
  /// ein kalibrierter Wert vorliegt (siehe [_onPosition]).
  final BarometerAltitudeService _barometerAltitudeService = BarometerAltitudeService();
  StreamSubscription<AltitudeReading>? _barometerSubscription;

  /// Aktuellster, gegen GPS kalibrierter Barometer-Höhenwert - null, sofern
  /// das Gerät kein Barometer besitzt oder noch keine erste GPS-Höhe zur
  /// Kalibrierung eingetroffen ist (siehe BarometerAltitudeService).
  double? _currentBarometerAltitudeMeters;

  /// NEU (README Abschnitt 55): true, wenn das Gerät keinen Drucksensor
  /// liefert - dann wird die GPS-Höhe verwendet, aber nur bei ausreichender
  /// Höhengenauigkeit ([_maxUsableGpsAltitudeAccuracyMeters]).
  bool _barometerUnavailable = false;

  /// GPS-Höhen mit schlechterer Genauigkeit (Meter) landen nicht im Track.
  static const double _maxUsableGpsAltitudeAccuracyMeters = 25;

  /// NEU (siehe README Abschnitt 29): Aktueller Kurs (Course over Ground,
  /// 0-360°) für die Momentanwerte-Anzeige auf dem Details-Tab der
  /// Track-Seite - siehe [_onPosition] für die Herkunft und
  /// Klassenkommentar dort für die Abgrenzung zum Magnetkompass der
  /// Kompass-Seite. null, solange noch kein gültiger Wert vorliegt.
  double? _currentHeadingDegrees;

  /// Unterhalb dieser GPS-Geschwindigkeit (1 m/s ~ 3,6 km/h) ist der
  /// GPS-Kurs (Course over Ground) unzuverlaessig und wird nicht angezeigt.
  static const double _minSpeedForHeadingMs = 1.0;

  /// Aeltere Kurswerte gelten als veraltet (bei Stillstand kommen wegen
  /// distanceFilter keine neuen Punkte mehr).
  static const Duration _headingMaxAge = Duration(seconds: 5);

  /// Kurs ueber Grund (GPS) - null bei Stillstand/Schritttempo, veraltetem
  /// Wert oder ausserhalb einer aktiven Aufzeichnung. Siehe
  /// [_currentHeadingDegrees].
  double? get currentHeadingDegrees {
    if (_state != RecordingState.recording) return null;
    final receivedAt = _lastPositionReceivedAt;
    if (receivedAt == null || DateTime.now().difference(receivedAt) > _headingMaxAge) {
      return null;
    }
    return _currentHeadingDegrees;
  }

  // ==== FEHLERKORREKTUR: Robustheit des Positions-Streams ====
  // Siehe README für den ausführlichen Hintergrund: Der Positions-Stream
  // hatte bislang GAR KEINE Fehlerbehandlung - ein Fehler (z. B. eine
  // PlatformException vom nativen Foreground-Service) führte dazu, dass
  // stillschweigend keine weiteren Punkte mehr eintrafen, ohne dass davon
  // irgendetwas in der App sichtbar wurde. [_startListening] versucht
  // jetzt bei einem Fehler oder einem unerwarteten Stream-Ende
  // automatisch einen Neustart, mit exponentiell steigender Wartezeit.

  /// Feste Eskalationsstufen für die Wartezeit vor einem erneuten
  /// Neustart-Versuch (Sekunden) - verhindert ein "Totlaufen" durch
  /// sofortige Endlos-Neuversuche, falls das zugrunde liegende Problem
  /// nicht kurzfristig behebbar ist (z. B. dauerhaft entzogene
  /// Standort-Berechtigung).
  static const List<int> _retryDelaysSeconds = [2, 4, 8, 16, 30];

  int _consecutiveStreamFailures = 0;
  Timer? _retryTimer;

  /// Zeitpunkt des letzten tatsächlich empfangenen GPS-Punkts - rein zu
  /// Diagnosezwecken, z. B. für eine mögliche künftige "seit X Minuten
  /// keine neuen Daten"-Anzeige. null, solange noch kein Punkt einer
  /// laufenden Aufzeichnung eingetroffen ist.
  DateTime? _lastPositionReceivedAt;

  /// Siehe [_lastPositionReceivedAt].
  DateTime? get lastPositionReceivedAt => _lastPositionReceivedAt;

  // ==== NEU: Checkpoint-Sicherung gegen Datenverlust ====
  // Siehe README für den Hintergrund: Bislang lebten die Punkte einer
  // laufenden Aufzeichnung AUSSCHLIESSLICH im Arbeitsspeicher - stirbt der
  // App-Prozess aus irgendeinem Grund unerwartet (z. B. durch ein noch
  // nicht abschließend geklärtes Zusammenspiel aus Android-
  // Hintergrundbeschränkungen und der persistenten FlutterEngine aus
  // Abschnitt 21), war die GESAMTE Aufzeichnung ersatzlos verloren - auch
  // wenn schon Stunden an Daten gesammelt worden waren. Die Aufzeichnung
  // wird deshalb jetzt periodisch als "Checkpoint" auf die Festplatte
  // geschrieben (siehe [_maybeSaveCheckpoint]) und beim nächsten
  // App-Start als wiederherstellbar erkannt (siehe
  // [checkForRecoverableCheckpoint]), falls sie nicht regulär beendet
  // wurde.
  static const _checkpointFileName = 'ontour_recording_checkpoint.json';
  static const Duration _minCheckpointInterval = Duration(seconds: 15);
  DateTime? _lastCheckpointSavedAt;

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

  /// Unterhalb dieser GPS-Geschwindigkeit (8 km/h, wie auf der Tacho-Seite)
  /// darf ein vom Bewegungssensor gemeldeter Stillstand die Aufzeichnung
  /// automatisch pausieren - der Beschleunigungssensor allein meldet bei
  /// ruhiger, gleichmaessiger Fahrt faelschlich "Stillstand".
  static const double _autoPauseMaxSpeedMs = 8 / 3.6;

  /// Kam so lange kein GPS-Punkt mehr, gilt der Stillstand ebenfalls als
  /// bestaetigt (distanceFilter 3 m: bei Bewegung kommen laufend Punkte).
  static const Duration _autoPauseStaleGpsAge = Duration(seconds: 5);

  // ==== NEU (README Abschnitt 49): Rein GPS-basierte Stillstandserkennung ====
  // Hintergrund: Im Leerlauf eines laufenden Motors halten die Vibrationen
  // den Beschleunigungssensor dauerhaft auf "Bewegung" - die bisherige
  // Erkennung (Sensor MELDET Stillstand, GPS bestaetigt) loeste dann nie
  // aus, und umgekehrt hob der Sensor eine Pause sofort wieder auf. Die
  // automatische Pause stuetzt sich deshalb jetzt auf GPS allein.

  /// Unterhalb dieser GPS-Geschwindigkeit (0,5 m/s = 1,8 km/h) gilt das
  /// Fahrzeug als stehend.
  static const double _gpsStandstillMaxSpeedMs = 0.5;

  /// So lange muss der Stillstand ununterbrochen anhalten, bevor
  /// automatisch pausiert wird - kurze Halts (Rollen, Anfahren) erzeugen
  /// so keine Pause.
  static const Duration _gpsStandstillConfirmDuration = Duration(seconds: 8);

  /// Ab dieser GPS-Geschwindigkeit (1,0 m/s = 3,6 km/h) - bewusst hoeher
  /// als die Pausenschwelle (Hysterese) - wird eine automatische Pause
  /// aufgehoben, aber erst nach [_gpsResumeConfirmations] aufeinander-
  /// folgenden Messwerten (GPS-Ausreisser im Stand).
  static const double _gpsResumeMinSpeedMs = 0.8;
  static const int _gpsResumeConfirmations = 2;

  /// Schneller Weg zum Fortsetzen: Bei distanceFilter 3 m trifft der erste
  /// Punkt nach dem Anfahren erst nach 3 m ein, der zweite nach weiteren 3 m
  /// - die doppelte Bestaetigung kostete daher spuerbar Zeit. Zeigt schon
  /// ein EINZELNER Punkt mindestens diese Geschwindigkeit (1,5 m/s =
  /// 5,4 km/h, im Stand durch GPS-Rauschen praktisch nicht erreichbar),
  /// wird sofort fortgesetzt.
  static const double _gpsResumeFastSpeedMs = 1.5;

  Timer? _standstillTimer;
  DateTime? _gpsStandstillSince;
  int _resumeSpeedStreak = 0;

  double? _lastSpeedMetersPerSecond;

  bool get _gpsConfirmsStandstill {
    final receivedAt = _lastPositionReceivedAt;
    if (receivedAt == null) return false;
    if (DateTime.now().difference(receivedAt) >= _autoPauseStaleGpsAge) return true;
    final speed = _lastSpeedMetersPerSecond;
    return speed != null && speed < _autoPauseMaxSpeedMs;
  }

  /// Reines GPS-Stillstandskriterium (siehe README Abschnitt 49): letzte
  /// Geschwindigkeit unter [_gpsStandstillMaxSpeedMs] ODER seit
  /// [_autoPauseStaleGpsAge] kein neuer Punkt (bei distanceFilter 3 m
  /// kommen im Stand keine neuen Punkte).
  bool get _gpsShowsStandstill {
    final receivedAt = _lastPositionReceivedAt;
    if (receivedAt == null) return false; // noch kein Fix
    if (DateTime.now().difference(receivedAt) >= _autoPauseStaleGpsAge) return true;
    final speed = _lastSpeedMetersPerSecond;
    return speed != null && speed < _gpsStandstillMaxSpeedMs;
  }

  /// true, solange ein GPS-Stream laufen soll: bei aktiver Aufzeichnung UND
  /// waehrend einer AUTOMATISCHEN Pause (dort nur zur Bewegungserkennung,
  /// es werden keine Punkte gespeichert).
  bool get _shouldListen =>
      _state == RecordingState.recording ||
      (_state == RecordingState.paused && _autoPaused);

  /// Aktuell konfigurierte Wartezeit für die Pause-Erinnerung (siehe
  /// README Abschnitt 22) - von außen aktuell zu halten (siehe
  /// [updateReminderOption]), da AppPreferences dieser Klasse nicht
  /// bekannt ist (TrackRecordingService bleibt bewusst unabhängig von
  /// konkreten Einstellungs-Klassen, siehe auch NorthLockButton/
  /// NauticalModeButton für dasselbe Prinzip bei anderen Widgets).
  int _reminderMinutes = 3;

  /// Muss von der aufrufenden Seite (siehe TrackPage) bei jeder relevanten
  /// Änderung erneut aufgerufen werden, damit eine in den Einstellungen
  /// geänderte Erinnerungs-Wartezeit berücksichtigt wird. Wirkt sich -
  /// analog zur Genauigkeitsstufe der Geschwindigkeitsmessung, siehe
  /// Abschnitt 4 - erst auf die NÄCHSTE Pause aus, nicht rückwirkend auf
  /// eine bereits laufende, bereits geplante Erinnerung.
  void updateReminderMinutes(int minutes) {
    _reminderMinutes = minutes;
  }

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
  ///
  /// NEU (siehe README Abschnitt 38): Jetzt `async` (vorher `void`) - falls
  /// die VORHERIGE Aufzeichnung erst vor sehr kurzer Zeit beendet wurde,
  /// wartet diese Methode zunächst [_minRestartGap], bevor der eigentliche
  /// Positions-Stream (re-)gestartet wird (siehe unten).
  Future<void> start() async {
    _points.clear();
    _distanceMeters = 0;
    _pausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _autoPaused = false;
    _manualResumeGraceUntil = null;
    _currentHeadingDegrees = null;
    _lastSpeedMetersPerSecond = null;
    _consecutiveStreamFailures = 0;
    _barometerUnavailable = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _lastPositionReceivedAt = null;
    _lastCheckpointSavedAt = null;
    _startTime = DateTime.now();
    _state = RecordingState.recording;
    _updatesController.add(null);
    // FEHLERKORREKTUR (siehe README Abschnitt 36): Log-Eintrag jetzt GANZ
    // AM ANFANG statt erst nach _startListening() - vorher hätte ein
    // synchroner Fehler beim Start des Positions-Streams (z. B. durch
    // eine fehlende Benachrichtigungs-Berechtigung, siehe unten) diesen
    // Eintrag nie erreicht, wodurch selbst das Diagnose-Protokoll darüber
    // keine Auskunft mehr hätte geben können.
    unawaited(DiagnosticLogService.instance.log('Aufzeichnung gestartet'));

    // NEU (siehe README Abschnitt 38): Wurde die VORHERIGE Aufzeichnung
    // erst vor sehr kurzer Zeit beendet, wird hier kurz gewartet, bevor
    // der Positions-Stream (re-)gestartet wird - siehe dortige
    // ausführliche Begründung (vermuteter Zusammenhang mit dem internen
    // Zustand des geolocator-Plugins bei mehrfach hintereinander
    // gestarteten/beendeten Foreground-Services).
    final lastStopped = _lastStoppedAt;
    if (lastStopped != null) {
      final elapsedSinceStop = DateTime.now().difference(lastStopped);
      if (elapsedSinceStop < _minRestartGap) {
        final remaining = _minRestartGap - elapsedSinceStop;
        unawaited(DiagnosticLogService.instance.log(
          'Warte ${remaining.inMilliseconds} ms vor Neustart des '
          'Positions-Streams (vorherige Aufzeichnung erst vor '
          '${elapsedSinceStop.inMilliseconds} ms beendet)',
        ));
        await Future<void>.delayed(remaining);
      }
    }

    try {
      _startListening();
    } catch (error, stackTrace) {
      // FEHLERKORREKTUR: _startListening() selbst hatte bislang KEINE
      // Absicherung gegen einen SYNCHRONEN Fehler (im Unterschied zu
      // asynchronen Stream-Fehlern, die bereits über onError/
      // _handleStreamError abgefangen werden, siehe dort) - z. B. wenn
      // Geolocator.getPositionStream() mit gesetztem
      // foregroundNotificationConfig direkt beim Aufruf scheitert, etwa
      // mangels Benachrichtigungs-Berechtigung. Ohne dieses try/catch
      // wäre ein solcher Fehler unbehandelt aus start() herausgeworfen
      // worden - die Aufzeichnung wäre äußerlich als "gestartet"
      // erschienen (state bereits auf recording gesetzt), OHNE dass
      // jemals ein GPS-Punkt eingetroffen wäre, und ohne jede sichtbare
      // Fehlermeldung.
      unawaited(DiagnosticLogService.instance.log('Fehler beim Start des Positions-Streams: $error'));
      _handleStreamError(error, stackTrace);
    }
    _startMotionListening();
    _startBarometerListening();
    _standstillTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _checkGpsStandstill());
  }

  /// NEU (README Abschnitt 49): Sekuendliche Pruefung des rein
  /// GPS-basierten Stillstands - loest die automatische Pause auch dann
  /// aus, wenn der Beschleunigungssensor wegen Motorvibrationen im
  /// Leerlauf nie "Stillstand" meldet.
  void _checkGpsStandstill() {
    if (_state != RecordingState.recording) {
      _gpsStandstillSince = null;
      return;
    }
    final now = DateTime.now();
    final graceUntil = _manualResumeGraceUntil;
    if (graceUntil != null && now.isBefore(graceUntil)) {
      _gpsStandstillSince = null;
      return;
    }
    if (!_gpsShowsStandstill) {
      _gpsStandstillSince = null;
      return;
    }
    final since = _gpsStandstillSince ??= now;
    if (now.difference(since) >= _gpsStandstillConfirmDuration) {
      _gpsStandstillSince = null;
      unawaited(DiagnosticLogService.instance.log('Automatische Pause durch GPS-Stillstand'));
      _autoPaused = true;
      unawaited(_pauseInternal());
    }
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

  /// NEU (siehe README Abschnitt 27): Startet - sofern noch nicht
  /// geschehen - das Beobachten der (gegen GPS kalibrierten) Barometer-
  /// Höhe, analog zu [_startMotionListening]. Läuft bewusst über die
  /// gesamte Aufzeichnung hinweg weiter, auch während einer Pause (der
  /// Sensor selbst verbraucht - anders als GPS - praktisch keinen
  /// nennenswerten zusätzlichen Akku) - so liegt nach einem Fortsetzen
  /// sofort wieder ein aktueller Wert vor, statt erst auf eine neue
  /// Kalibrierung warten zu müssen.
  void _startBarometerListening() {
    _barometerSubscription ??= _barometerAltitudeService.altitudeStream().listen(
      (reading) => _currentBarometerAltitudeMeters = reading.altitudeMeters,
      onError: (Object error) {
        _barometerUnavailable = true;
        // Gerät ohne Barometer (oder ein sonstiger Sensor-Fehler) - dann
        // bleibt es bei der GPS-Rohhöhe (siehe _onPosition), kein
        // Absturz. WICHTIG: Ohne diesen expliziten onError-Handler würde
        // ein vom Sensor gemeldeter Fehler als unbehandelter Stream-
        // Fehler durchschlagen (siehe BarometerAltitudeService, die
        // Fehler bewusst über den Controller weiterreicht statt sie
        // selbst zu verschlucken).
      },
    );
  }

  Future<void> _stopBarometerListening() async {
    await _barometerSubscription?.cancel();
    _barometerSubscription = null;
    _currentBarometerAltitudeMeters = null;
    await _barometerAltitudeService.dispose();
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

      // Nur pausieren, wenn auch GPS einen Stillstand bestaetigt (siehe
      // _gpsConfirmsStandstill) - der Beschleunigungssensor allein meldet
      // bei ruhiger, gleichmaessiger Fahrt faelschlich "Stillstand".
      if (!_gpsConfirmsStandstill) return;

      // Stillstand waehrend aktiver Aufzeichnung erkannt - automatisch
      // pausieren (gesammelte Punkte bleiben erhalten, siehe
      // _pauseInternal).
      _autoPaused = true;
      _pauseInternal();
    }
    // GEAENDERT (README Abschnitt 49): Eine automatische Pause wird NICHT
    // mehr durch den Bewegungssensor aufgehoben - Motorvibrationen im
    // Leerlauf wuerden sie sonst sofort wieder beenden. Das Fortsetzen
    // erfolgt ausschliesslich ueber die GPS-Geschwindigkeit (siehe
    // _onPosition).
  }

  void _startListening() {
    if (_subscription != null) return;
    _subscription = Geolocator.getPositionStream(
      // AndroidSettings statt der bisherigen plattformneutralen
      // LocationSettings - beide Klassen kommen aus demselben Paket
      // `geolocator` (das die Android-spezifische Klasse aus
      // `geolocator_android` für Android bequem mit re-exportiert), ein
      // zusätzlicher pubspec-Eintrag ist dafür nicht nötig. Passend dazu,
      // dass diese App bewusst ausschließlich auf Android läuft (siehe
      // README), ist das hier unbedingt.
      locationSettings: AndroidSettings(
        accuracy: fixedAccuracy,
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
    ).listen(
      _onPosition,
      onError: _handleStreamError,
      onDone: _handleStreamDone,
      // WICHTIG (Fehlerkorrektur): Ohne cancelOnError: false würde der
      // Stream nach dem ERSTEN Fehler automatisch abgebrochen - der
      // Fehler würde zwar noch an onError gemeldet, ein erneuter,
      // eigenständiger Neustartversuch über [_startListening] wäre
      // danach aber wirkungslos, solange die (dann bereits tote)
      // Subscription noch als "vorhanden" gilt. Wir werten den Fehler
      // selbst aus und entscheiden dort bewusst, ob/wie neu gestartet
      // wird (siehe [_handleStreamError]).
      cancelOnError: false,
    );
  }

  /// FEHLERKORREKTUR: Der Positions-Stream hatte bislang GAR KEINE
  /// Fehlerbehandlung - ein Fehler (z. B. eine `PlatformException` vom
  /// nativen Foreground-Service, etwa durch Android-Einschränkungen beim
  /// (Neu-)Starten eines Foreground-Service aus dem Hintergrund heraus)
  /// führte dazu, dass STILLSCHWEIGEND keine weiteren Punkte mehr
  /// eintrafen, ohne dass davon irgendetwas in der App sichtbar wurde -
  /// die Aufzeichnung "fror" faktisch ein, obwohl `state` weiterhin
  /// `recording` blieb. Versucht jetzt automatisch einen Neustart, mit
  /// exponentiell steigender Wartezeit zwischen den Versuchen (siehe
  /// [_retryDelaysSeconds]).
  void _handleStreamError(Object error, StackTrace stackTrace) {
    _subscription = null;
    if (!_shouldListen) return; // inzwischen manuell pausiert/beendet

    _consecutiveStreamFailures++;
    final delayIndex = (_consecutiveStreamFailures - 1).clamp(0, _retryDelaysSeconds.length - 1);
    final delay = Duration(seconds: _retryDelaysSeconds[delayIndex]);

    // NEU (siehe README Abschnitt 33/34): Genau der Fall, den das
    // Diagnose-Protokoll ursprünglich sichtbar machen sollte - ein
    // Stream-Fehler bzw. ein unerwartetes Stream-Ende während einer
    // laufenden Aufzeichnung.
    unawaited(DiagnosticLogService.instance.log(
      'Stream-Fehler (Versuch $_consecutiveStreamFailures, '
      'Neustart in ${delay.inSeconds}s): $error',
    ));

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_shouldListen) _startListening();
    });
  }

  /// Ein regulär (ohne Fehler) beendeter Stream ist im weiterhin
  /// laufenden Zustand unerwartet - dieselbe Neustart-Logik wie bei
  /// [_handleStreamError].
  void _handleStreamDone() {
    _handleStreamError(
      StateError('Positions-Stream unerwartet beendet (onDone)'),
      StackTrace.current,
    );
  }

  void _onPosition(Position position) {
    // GPS-Geschwindigkeit wird immer mitgefuehrt (auch waehrend einer
    // automatischen Pause), siehe _gpsConfirmsStandstill.
    final validSpeed = position.speed.isFinite && position.speed >= 0 ? position.speed : null;
    _lastSpeedMetersPerSecond = validSpeed;
    _lastPositionReceivedAt = DateTime.now();
    // Erfolgreich empfangener Punkt bestaetigt, dass der Stream gesund ist.
    _consecutiveStreamFailures = 0;

    // Kurs ueber Grund (GPS) nur bei echter Bewegung gueltig - NICHT der
    // Magnetkompass der Kompass-Seite.
    _currentHeadingDegrees = (validSpeed != null &&
            validSpeed >= _minSpeedForHeadingMs &&
            position.heading.isFinite &&
            position.heading >= 0)
        ? position.heading
        : null;

    // Automatische Pause: keinen Punkt aufzeichnen, nur pruefen, ob GPS
    // Bewegung zeigt - dann automatisch fortsetzen (auch bei ruhiger Fahrt,
    // bei der der Beschleunigungssensor allein nahe 0 bleiben wuerde).
    if (_state == RecordingState.paused && _autoPaused) {
      if (validSpeed != null && validSpeed >= _gpsResumeMinSpeedMs) {
        _resumeSpeedStreak++;
        if (validSpeed >= _gpsResumeFastSpeedMs ||
            _resumeSpeedStreak >= _gpsResumeConfirmations) {
          _resumeSpeedStreak = 0;
          unawaited(DiagnosticLogService.instance.log(
            'Automatisches Fortsetzen durch GPS-Geschwindigkeit '
            '(${(validSpeed * 3.6).toStringAsFixed(1)} km/h)',
          ));
          resume(manual: false);
        }
      } else {
        _resumeSpeedStreak = 0;
      }
      return;
    }
    if (_state != RecordingState.recording) return;

    // NEU (README Abschnitt 27): Kalibriert den Barometer laufend gegen
    // die aktuelle GPS-Höhe (siehe BarometerAltitudeService, Abschnitt
    // 10) - dieselbe GPS-Messung, die ohnehin für den Trackpunkt selbst
    // verwendet wird; ein zusätzlicher, eigener Standort-Stream (wie ihn
    // die Kompass-Seite über AltitudeService nutzt) ist dafür NICHT
    // nötig.
    final positionAccuracy =
        position.accuracy.isFinite && position.accuracy >= 0 ? position.accuracy : null;
    // NEU (README Abschnitt 54): NN-Korrektur (Android MSL) auf die
    // GPS-Höhe, bevor sie als Referenz dient bzw. gespeichert wird.
    final correction = AltitudeCorrection.instance;
    final gpsReference = position.altitude.isFinite ? correction.gpsReference(position.altitude) : null;
    unawaited(correction.refreshIfDue(
      dartAltitude: position.altitude,
      shownAltitude: _currentBarometerAltitudeMeters != null ? correction.display(_currentBarometerAltitudeMeters!) : null,
    ));
    _barometerAltitudeService.calibrate(
      referenceAltitudeMeters: gpsReference ?? position.altitude,
      referenceLatitude: position.latitude,
      referenceLongitude: position.longitude,
      referencePositionAccuracyMeters: positionAccuracy,
      referenceAltitudeAccuracyMeters:
          position.altitudeAccuracy.isFinite ? position.altitudeAccuracy : null,
    );

    // NEU (README Abschnitt 27): Bevorzugt die präzisere, kalibrierte
    // Barometer-Höhe gegenüber der GPS-Rohhöhe, sobald ein kalibrierter
    // Wert vorliegt (analog zur Kompass-Seite, siehe Abschnitt 10) -
    // andernfalls (Gerät ohne Barometer, oder noch keine Kalibrierung
    // erfolgt) fällt es auf die GPS-Rohhöhe zurück.
    // NEU (README Abschnitt 55): Die Höhe landet erst im Track, wenn sie
    // genau genug ist - Positionsdaten sind davon NICHT betroffen. Mit
    // Barometer: erst ab der ersten gegen brauchbares GPS kalibrierten
    // Höhe. Ohne Barometer: GPS-Höhe nur bei ausreichender
    // Höhengenauigkeit (0 = keine Angabe des Systems, wird akzeptiert).
    double? baseAltitude;
    if (_currentBarometerAltitudeMeters != null) {
      baseAltitude = _currentBarometerAltitudeMeters;
    } else if (_barometerUnavailable && gpsReference != null) {
      final accuracy = position.altitudeAccuracy;
      final usable = !accuracy.isFinite || accuracy <= 0 || accuracy <= _maxUsableGpsAltitudeAccuracyMeters;
      if (usable) baseAltitude = gpsReference;
    }
    // Manueller Versatz (README Abschnitt 54) nur auf den Endwert.
    final altitude = baseAltitude != null ? correction.display(baseAltitude) : null;

    // NEU (README Abschnitt 29): Momentan-Geschwindigkeit für das
    // Geschwindigkeitsprofil - dieselbe Behandlung von Messrauschen
    // (vereinzelt knapp negative Werte) wie in SpeedService, siehe
    // Abschnitt 6/15.
    final speed = position.speed.isFinite && position.speed >= 0 ? position.speed : null;

    // NEU (README Abschnitt 29): Aktueller Kurs (Course over Ground, aus
    // dem GPS-Signal - NICHT der Magnetkompass der Kompass-Seite, siehe
    // dortiger Klassenkommentar) für die Momentanwerte-Anzeige auf dem
    // Details-Tab. Bewusst NICHT Teil von TrackPoint/RecordedTrack -
    // anders als Geschwindigkeit gibt es dafür kein "Kursprofil", der
    // Wert wird nur für die LIVE-Anzeige benötigt und deshalb rein
    // ephemer gehalten (siehe currentHeadingDegrees).

    final point = TrackPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeMeters: altitude,
      speedMetersPerSecond: speed,
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
    // NEU: Sichert die Aufzeichnung periodisch auf die Festplatte (siehe
    // Klassenkommentar bei _checkpointFileName) - bewusst NICHT awaited,
    // eine Datei-Schreiboperation soll den laufenden Empfang weiterer
    // GPS-Punkte nicht verzögern; ein einzelner fehlgeschlagener
    // Schreibversuch (z. B. kurzzeitig voller Speicher) wird beim
    // nächsten Punkt einfach erneut versucht.
    unawaited(_maybeSaveCheckpoint());
  }

  /// Schreibt die bisher gesammelten Punkte als Checkpoint-Datei, sofern
  /// seit dem letzten Schreibvorgang mindestens [_minCheckpointInterval]
  /// vergangen ist (verhindert übermäßig häufige Datei-I/O bei dicht
  /// aufeinanderfolgenden GPS-Punkten). Bewusst EIGENE, von
  /// [TrackStorageService] getrennte Datei außerhalb von dessen
  /// `tracks/`-Verzeichnis - so taucht ein Checkpoint niemals versehentlich
  /// in der Liste gespeicherter Tracks auf (siehe TrackStorageService.loadAll).
  Future<void> _maybeSaveCheckpoint() async {
    final now = DateTime.now();
    if (_lastCheckpointSavedAt != null &&
        now.difference(_lastCheckpointSavedAt!) < _minCheckpointInterval) {
      return;
    }
    final start = _startTime;
    if (start == null || _points.isEmpty) return;

    try {
      final file = await _checkpointFile();
      final json = {
        'startTime': start.toIso8601String(),
        'points': _points.map((p) => p.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(json));
      _lastCheckpointSavedAt = now;
      // NEU (README Abschnitt 33/34): Bewusst knapp gehalten (kein
      // Punkte-Dump) - dient hier nur als "Herzschlag"-Nachweis, dass die
      // Aufzeichnung bis zu diesem Zeitpunkt noch aktiv lief, falls der
      // Prozess danach unerwartet endet.
      unawaited(
        DiagnosticLogService.instance.log('Checkpoint gesichert (${_points.length} Punkte)'),
      );
    } catch (_) {
      // Checkpoint ist ein reines Sicherheitsnetz - ein fehlgeschlagener
      // Schreibversuch darf die eigentliche Aufzeichnung nicht
      // beeinträchtigen, siehe Aufrufstelle.
    }
  }

  Future<File> _checkpointFile() async {
    final documents = await getApplicationDocumentsDirectory();
    return File('${documents.path}/$_checkpointFileName');
  }

  /// Löscht eine ggf. vorhandene Checkpoint-Datei - aufgerufen bei jedem
  /// REGULÄREN Ende einer Aufzeichnung ([stop]/[discard]), da sie dann
  /// nicht mehr gebraucht wird (der eigentliche Track ist entweder
  /// gespeichert oder bewusst verworfen).
  Future<void> _deleteCheckpointIfExists() async {
    try {
      final file = await _checkpointFile();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Sicherheitsnetz - siehe _maybeSaveCheckpoint.
    }
  }

  /// Prüft, ob eine Checkpoint-Datei von einer VORHERIGEN, nicht regulär
  /// beendeten Aufzeichnung existiert (siehe Klassenkommentar) - liefert
  /// bei Fund einen vorläufigen [RecordedTrack] daraus (Distanz bereits
  /// aus den Punkten berechnet, Dauer als Differenz letzter/erster
  /// Zeitstempel - eine über [TrackRecordingService] selbst geführte,
  /// pausenbereinigte Dauer gibt es für eine sooo rekonstruierte
  /// Aufzeichnung naturgemäß nicht mehr), sonst `null`. Löscht die Datei
  /// NICHT selbst - das obliegt der aufrufenden Seite erst NACH einer
  /// bewussten Entscheidung des Nutzers (retten oder verwerfen), siehe
  /// [discardRecoverableCheckpoint].
  ///
  /// WICHTIG: Sollte nur aufgerufen werden, solange [state] noch `idle`
  /// ist (vor dem Start einer neuen Aufzeichnung) - siehe TrackPage.
  Future<RecordedTrack?> checkForRecoverableCheckpoint() async {
    try {
      final file = await _checkpointFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final startTime = DateTime.parse(json['startTime'] as String);
      final points = (json['points'] as List)
          .map((p) => TrackPoint.fromJson(p as Map<String, dynamic>))
          .toList();
      if (points.length < 2) {
        // Zu wenige Punkte für einen sinnvollen Track (z. B. Checkpoint
        // unmittelbar nach dem allerersten Punkt geschrieben, dann
        // Prozessabbruch) - Datei direkt aufräumen, nichts zum Retten.
        await file.delete();
        return null;
      }

      var distanceMeters = 0.0;
      for (var i = 1; i < points.length; i++) {
        distanceMeters += Geolocator.distanceBetween(
          points[i - 1].latitude,
          points[i - 1].longitude,
          points[i].latitude,
          points[i].longitude,
        );
      }
      final endTime = points.last.timestamp;

      return RecordedTrack(
        id: startTime.millisecondsSinceEpoch.toString(),
        name: 'Wiederhergestellte Aufzeichnung vom '
            '${startTime.day.toString().padLeft(2, '0')}.'
            '${startTime.month.toString().padLeft(2, '0')}.${startTime.year}, '
            '${startTime.hour.toString().padLeft(2, '0')}:'
            '${startTime.minute.toString().padLeft(2, '0')}',
        startTime: startTime,
        endTime: endTime,
        points: points,
        distanceMeters: distanceMeters,
        recordedDuration: endTime.difference(startTime),
      );
    } catch (_) {
      // Beschädigte/unlesbare Checkpoint-Datei - analog zu
      // TrackStorageService.loadAll lieber überspringen als abzustürzen.
      return null;
    }
  }

  /// Löscht eine Checkpoint-Datei, nachdem der Nutzer sich BEWUSST gegen
  /// eine Wiederherstellung entschieden hat (siehe
  /// [checkForRecoverableCheckpoint]). Nach einer erfolgreichen
  /// Wiederherstellung (Track wurde uebernommen und ueber
  /// TrackStorageService gespeichert) ruft die aufrufende Seite
  /// ebenfalls diese Methode auf, um die Checkpoint-Datei danach zu
  /// entfernen.
  Future<void> discardRecoverableCheckpoint() => _deleteCheckpointIfExists();

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
      final wasAutoPaused = _autoPaused;
      _autoPaused = false;
      if (wasAutoPaused) {
        // Manuell "verfestigte" Pause: GPS-Stream beenden wie bei jeder
        // manuellen Pause.
        await _subscription?.cancel();
        _subscription = null;
      }
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
    // Bei AUTOMATISCHER Pause bleibt der GPS-Stream aktiv (nur zur
    // Bewegungserkennung, es werden keine Punkte gespeichert) - bei
    // manueller Pause wird er wie bisher beendet.
    if (!_autoPaused) {
      await _subscription?.cancel();
      _subscription = null;
    }
    _pauseStartedAt = DateTime.now();
    _resumeSpeedStreak = 0;
    _state = RecordingState.paused;
    _updatesController.add(null);
    unawaited(DiagnosticLogService.instance.log(
      'Pausiert (${_autoPaused ? 'automatisch, Stillstand' : 'manuell'}), '
      '${_points.length} Punkte bisher',
    ));
    // NEU (README Abschnitt 22): Plant die Erinnerungs-Benachrichtigung -
    // bewusst hier im gemeinsamen Pfad für MANUELLE und AUTOMATISCHE
    // Pause (nicht nur bei Stillstand), da eine "vergessene" Aufzeichnung
    // in beiden Fällen gleichermaßen droht.
    await _scheduleReminderIfEnabled();
  }

  /// Plant über den nativen `AlarmManager` (siehe _reminderChannel) eine
  /// Erinnerungs-Benachrichtigung, sofern der Nutzer in den Einstellungen
  /// nicht "Aus" gewählt hat (siehe AppPreferences.autoPauseReminderMinutes). Ein
  /// Fehlschlag (z. B. weil die native Implementierung fehlt) darf die
  /// eigentliche Aufzeichnung nicht beeinträchtigen - deshalb wird ein
  /// Fehler hier bewusst nur verschluckt, nicht weitergereicht.
  Future<void> _scheduleReminderIfEnabled() async {
    final minutes = _reminderMinutes;
    if (minutes <= 0) return; // 0 = Erinnerung aus
    try {
      await _reminderChannel.invokeMethod<void>('schedule', {'delayMinutes': minutes});
    } catch (_) {
      // Die Erinnerung ist ein reiner Komfort-Zusatz - siehe Kommentar
      // oben.
    }
  }

  /// Storniert eine zuvor geplante Erinnerung (siehe
  /// [_scheduleReminderIfEnabled]) - wird bei jedem Verlassen des
  /// pausierten Zustands aufgerufen (Fortsetzen, Beenden, Verwerfen),
  /// unabhängig davon, ob überhaupt eine Erinnerung aktiv war (ein
  /// Stornieren einer nicht existierenden Erinnerung ist auf nativer
  /// Seite ein harmloser No-op).
  Future<void> _cancelReminder() async {
    try {
      await _reminderChannel.invokeMethod<void>('cancel');
    } catch (_) {
      // Siehe _scheduleReminderIfEnabled - reiner Komfort-Zusatz.
    }
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
    _resumeSpeedStreak = 0;
    _gpsStandstillSince = null;
    if (manual) {
      _manualResumeGraceUntil = DateTime.now().add(_manualResumeGracePeriod);
    }
    _state = RecordingState.recording;
    _updatesController.add(null);
    _startListening();
    unawaited(DiagnosticLogService.instance.log(
      'Fortgesetzt (${manual ? 'manuell' : 'automatisch, Bewegung erkannt'})',
    ));
    // NEU (README Abschnitt 22): Eine ggf. für die jetzt beendete Pause
    // geplante Erinnerung wird nicht mehr gebraucht.
    unawaited(_cancelReminder());
  }

  /// Beendet die Aufzeichnung endgültig und liefert das Ergebnis als
  /// [RecordedTrack] - null, falls weniger als zwei Punkte gesammelt
  /// wurden (z. B. bei sofortigem Abbruch), da ein Track mit nur einem
  /// Punkt fachlich keinen Sinn ergibt.
  Future<RecordedTrack?> stop({required String name}) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _standstillTimer?.cancel();
    _standstillTimer = null;
    _gpsStandstillSince = null;
    await _subscription?.cancel();
    _subscription = null;
    await _stopMotionListening();
    // NEU (README Abschnitt 27): Barometer wird nur während einer
    // Aufzeichnung benötigt (siehe Klassenkommentar bei
    // _startBarometerListening).
    await _stopBarometerListening();
    // NEU (README Abschnitt 22): Egal ob gerade pausiert oder nicht - eine
    // ggf. noch geplante Erinnerung ist mit dem endgültigen Beenden
    // hinfällig.
    await _cancelReminder();
    // NEU: Checkpoint wird beim regulären Beenden nicht mehr gebraucht -
    // der Track ist entweder (wenige Zeilen weiter unten) als
    // RecordedTrack zurückgegeben und wird von der aufrufenden Seite
    // gespeichert, oder es waren zu wenige Punkte für einen gültigen
    // Track.
    await _deleteCheckpointIfExists();
    final wasActive = _state != RecordingState.idle;
    final recordedElapsed = elapsed;
    final start = _startTime;
    _autoPaused = false;
    _manualResumeGraceUntil = null;
    _state = RecordingState.idle;
    // NEU (siehe README Abschnitt 38): Grundlage für die Mindest-
    // Wartezeit in start(), siehe _minRestartGap.
    _lastStoppedAt = DateTime.now();
    _updatesController.add(null);
    unawaited(DiagnosticLogService.instance.log(
      'Beendet: "$name", ${_points.length} Punkte, '
      '${_distanceMeters.toStringAsFixed(0)} m',
    ));

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
    _retryTimer?.cancel();
    _retryTimer = null;
    _standstillTimer?.cancel();
    _standstillTimer = null;
    _gpsStandstillSince = null;
    await _subscription?.cancel();
    _subscription = null;
    await _stopMotionListening();
    // NEU (README Abschnitt 27): siehe Kommentar in stop().
    await _stopBarometerListening();
    // NEU (README Abschnitt 22): siehe Kommentar in stop().
    await _cancelReminder();
    // NEU: siehe Kommentar in stop().
    await _deleteCheckpointIfExists();
    unawaited(DiagnosticLogService.instance.log('Verworfen (${_points.length} Punkte)'));
    _points.clear();
    _distanceMeters = 0;
    _pausedDuration = Duration.zero;
    _pauseStartedAt = null;
    _autoPaused = false;
    _manualResumeGraceUntil = null;
    _currentHeadingDegrees = null;
    _startTime = null;
    _state = RecordingState.idle;
    // NEU (siehe README Abschnitt 38): siehe Kommentar in stop().
    _lastStoppedAt = DateTime.now();
    _updatesController.add(null);
  }

  /// Muss aufgerufen werden, wenn die App komplett beendet wird (siehe
  /// HomeShell.dispose) - NICHT beim einfachen Verlassen der Track-Seite,
  /// da eine laufende Aufzeichnung ja gerade dann weiterlaufen soll.
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _standstillTimer?.cancel();
    await _subscription?.cancel();
    await _stopMotionListening();
    await _stopBarometerListening();
    await _updatesController.close();
  }
}
