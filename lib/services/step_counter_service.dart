import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostic_log_service.dart';

/// Zustand des Schrittsensors (Gerät und Berechtigung).
enum StepSensorState {
  checking,
  unavailable,
  permissionDenied,
  permissionDeniedForever,
  ready,
}

/// Woher der Tagesbeginn (Basiszählerstand) stammt - bestimmt, wie genau die
/// Tageszahl ist (siehe [StepCounterService.stepsToday]).
enum StepBaselineKind {
  /// Zählerstand von Mitternacht (Alarm) - exakt.
  midnight,

  /// Gerät wurde heute neu gestartet, Zähler beginnt bei 0 - Schritte vor dem
  /// Neustart fehlen.
  sinceBoot,

  /// Erste Messung des Tages durch die App - Schritte davor fehlen.
  firstReading,
}

/// Schrittzähler auf Basis des Android-Sensors TYPE_STEP_COUNTER (siehe
/// README Abschnitt 72, native Seite: StepCounterBridge.kt).
///
/// Der Sensor liefert die Gesamtzahl der Schritte seit dem Geräte-Neustart.
/// Beide Zählweisen sind Differenzen davon:
/// - TAGESZAHL = aktueller Zählerstand minus Zählerstand von Mitternacht.
/// - AUFZEICHNUNG = aktueller Zählerstand minus Zählerstand beim Start einer
///   Track-Aufzeichnung (abzüglich der Schritte während manueller Pausen).
///
/// Lebt - wie TrackRecordingService und PressureTrendService - einmalig in
/// HomeShell. Der Sensor wird nur abonniert, solange es Abnehmer gibt
/// ([acquire]/[release]): die Start-Seite, solange eine Schritte-Kachel
/// belegt ist, und eine laufende Track-Aufzeichnung.
///
/// Die Berechtigung ACTIVITY_RECOGNITION wird NICHT automatisch abgefragt,
/// sondern nur auf ausdrücklichen Wunsch ([requestPermission], Antippen der
/// Kachel).
class StepCounterService {
  static const MethodChannel _channel = MethodChannel('ontour/steps');
  static const EventChannel _eventChannel = EventChannel('ontour/steps_stream');

  /// Zwei Boot-Zeitpunkte gelten als "derselbe Start", wenn sie weniger als
  /// diese Zeit auseinanderliegen (Uhr-Korrekturen verschieben den
  /// berechneten Wert um Sekunden).
  static const int _bootToleranceMs = 120000;

  static const _firstDayKey = 'stepsFirstReadingDay';
  static const _firstCounterKey = 'stepsFirstReadingCounter';
  static const _firstBootKey = 'stepsFirstReadingBoot';

  final StreamController<void> _updates = StreamController<void>.broadcast();

  StepSensorState _state = StepSensorState.checking;
  bool _availabilityChecked = false;
  int _consumers = 0;
  StreamSubscription<dynamic>? _subscription;
  Timer? _dayTimer;

  /// Letzter Zählerstand - nur gültig, solange der Stream läuft (sonst null).
  int? _latestCounter;

  /// Einzelschritte des Schritt-Detektors, die der (verzögert meldende)
  /// Zähler noch nicht eingerechnet hat. Der Hardware-Zähler meldet auf
  /// vielen Geräten nur in Paketen alle paar Sekunden; der Detektor meldet
  /// jeden Schritt sofort. Jede Zähler-Meldung verbraucht die vorgemerkten
  /// Schritte wieder (siehe [_onEvent]) - so wird nichts doppelt gezählt.
  int _pending = 0;
  static const int _maxPending = 30;

  // Diagnose (Antippen der Kachel zeigt sie): Wie viele Meldungen kamen an?
  int _counterEvents = 0;
  int _detectorEvents = 0;
  DateTime? _lastEventAt;

  /// Kurzer Diagnosetext für die Fehlersuche (Antippen der Schritte-Kachel).
  String get debugSummary {
    final at = _lastEventAt;
    final ago = at == null ? 'nie' : 'vor ${DateTime.now().difference(at).inSeconds} s';
    return 'Zähler ${_latestCounter ?? '-'} · Tagesbasis ${_dayBaseline ?? '-'} · '
        'vorgemerkt $_pending · Zähler-Meldungen $_counterEvents · '
        'Einzelschritte $_detectorEvents · letzte Meldung $ago · '
        'Abnehmer $_consumers · Zustand ${_state.name}';
  }

  /// Zählerstand inkl. noch nicht eingerechneter Einzelschritte.
  int? get _liveCount {
    final latest = _latestCounter;
    return latest == null ? null : latest + _pending;
  }

  // ==== Tageszahl ====
  int? _dayBaseline;
  String? _baselineDay;
  StepBaselineKind? _baselineKind;
  bool _baselineResolving = false;

  // ==== Zählung während einer Aufzeichnung ====
  bool _sessionActive = false;
  bool _sessionPaused = false;
  bool _sessionAcquired = false;
  int? _sessionStart;
  int _sessionPausedSteps = 0;
  int? _pauseStartCounter;

  StepSensorState get state => _state;

  /// Feuert bei jeder Änderung (neuer Zählerstand, Zustandswechsel).
  Stream<void> get updates => _updates.stream;

  /// true, solange eine Track-Aufzeichnung (auch pausiert) mitgezählt wird.
  bool get sessionActive => _sessionActive;

  /// Herkunft des heutigen Tagesbeginns - null, solange nicht bekannt.
  StepBaselineKind? get todayBaselineKind =>
      _baselineDay == _dayKey(DateTime.now()) ? _baselineKind : null;

  /// Schritte heute - null, solange kein Wert vorliegt.
  int? get stepsToday {
    final live = _liveCount;
    final baseline = _dayBaseline;
    if (live == null || baseline == null) return null;
    if (_baselineDay != _dayKey(DateTime.now())) return null;
    return math.max(0, live - baseline);
  }

  /// Schritte der laufenden Aufzeichnung (manuelle Pausen herausgerechnet) -
  /// null ohne laufende Aufzeichnung oder ohne Sensorwert.
  int? get sessionSteps {
    if (!_sessionActive) return null;
    final start = _sessionStart;
    final live = _liveCount;
    if (start == null || live == null) return null;
    final end = _sessionPaused ? (_pauseStartCounter ?? live) : live;
    return math.max(0, end - start - _sessionPausedSteps);
  }

  // ==== Zustand/Berechtigung ====

  Future<void> init() => refreshPermission();

  Future<void> _checkAvailability() async {
    try {
      final available = await _channel.invokeMethod<bool>('available') ?? false;
      if (!available) _state = StepSensorState.unavailable;
    } catch (_) {
      _state = StepSensorState.unavailable;
    }
    _availabilityChecked = true;
  }

  /// Liest den aktuellen Berechtigungsstatus neu ein (beim Start, beim
  /// Zurückkehren in den Vordergrund und beim Öffnen der Start-Seite - der
  /// Nutzer kann die Berechtigung in den Android-Einstellungen geändert
  /// haben).
  Future<void> refreshPermission() async {
    if (!_availabilityChecked) await _checkAvailability();
    if (_state == StepSensorState.unavailable) {
      _notify();
      return;
    }

    final PermissionStatus status;
    try {
      status = await Permission.activityRecognition.status;
    } catch (_) {
      return;
    }
    final StepSensorState next;
    if (status.isGranted) {
      next = StepSensorState.ready;
    } else if (status.isPermanentlyDenied) {
      next = StepSensorState.permissionDeniedForever;
    } else {
      next = StepSensorState.permissionDenied;
    }
    final changed = next != _state;
    _state = next;

    if (_state == StepSensorState.ready) {
      unawaited(_scheduleMidnight());
      if (_consumers > 0) _startStream();
    } else {
      _stopStream();
    }
    if (changed) _notify();
  }

  /// Fragt die Berechtigung ab (bzw. öffnet bei dauerhafter Ablehnung die
  /// App-Einstellungen) - nur auf ausdrücklichen Wunsch des Nutzers.
  Future<StepSensorState> requestPermission() async {
    if (_state == StepSensorState.unavailable) return _state;
    try {
      final current = await Permission.activityRecognition.status;
      if (current.isPermanentlyDenied) {
        await openAppSettings();
        // Nach der Rückkehr aktualisiert HomeShell den Status (resumed).
        return _state;
      }
      await Permission.activityRecognition.request();
    } catch (_) {
      // Ohne Berechtigungsdialog bleibt es beim bisherigen Zustand.
    }
    await refreshPermission();
    return _state;
  }

  Future<void> _scheduleMidnight() async {
    try {
      await _channel.invokeMethod<void>('scheduleMidnight');
    } catch (_) {
      // Reiner Zusatz - ohne Alarm wird die Tageszahl ersatzweise ab der
      // ersten Messung des Tages gezählt (siehe [StepBaselineKind]).
    }
  }

  // ==== Abnehmer (Sensor nur bei Bedarf) ====

  void acquire() {
    _consumers++;
    if (_state == StepSensorState.ready) {
      _startStream();
    } else if (_state != StepSensorState.unavailable) {
      unawaited(refreshPermission());
    }
  }

  void release() {
    if (_consumers > 0) _consumers--;
    if (_consumers == 0) _stopStream();
  }

  void _startStream() {
    if (_subscription != null) return;
    _counterEvents = 0;
    _detectorEvents = 0;
    _lastEventAt = null;
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onStreamError,
    );
    _dayTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => _checkDayRollover());
  }

  void _stopStream() {
    _subscription?.cancel();
    _subscription = null;
    _dayTimer?.cancel();
    _dayTimer = null;
    _latestCounter = null;
    _pending = 0;
  }

  void _onStreamError(Object error) {
    _stopStream();
    if (error is PlatformException && error.code == 'unavailable') {
      _state = StepSensorState.unavailable;
    } else {
      // Sensor ließ sich nicht aktivieren - meist fehlende Berechtigung.
      _state = StepSensorState.permissionDenied;
    }
    _notify();
  }

  /// Verarbeitet eine Sensor-Meldung der nativen Seite: `{t: 'c', v: Zähler}`
  /// (Hardware-Zähler, verzögert) oder `{t: 's', v: 1}` (ein einzelner
  /// Schritt, sofort).
  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final value = event['v'];
    if (value is! num) return;

    _lastEventAt = DateTime.now();
    if (event['t'] == 's') {
      _detectorEvents++;
      // Ohne Zählerstand fehlt die Bezugsbasis - erst nach der ersten
      // Zähler-Meldung (kommt direkt nach dem Start) mitzählen.
      if (_latestCounter == null) return;
      _pending = math.min(_pending + 1, _maxPending);
    } else {
      _counterEvents++;
      final counter = value.toInt();
      final previous = _latestCounter;
      if (previous != null && counter > previous) {
        _pending = math.max(0, _pending - (counter - previous));
      }
      _latestCounter = counter;
    }

    final live = _liveCount;
    if (_sessionActive && live != null) {
      _sessionStart ??= live;
      if (_sessionPaused) _pauseStartCounter ??= live;
    }
    final latest = _latestCounter;
    if (latest != null && (_dayBaseline == null || _baselineDay != _dayKey(DateTime.now()))) {
      unawaited(_resolveBaseline(latest));
    }
    _notify();
  }

  /// Erkennt den Tageswechsel auch dann, wenn gerade keine Schritte gezählt
  /// werden (im Stand kommen keine Sensorwerte).
  void _checkDayRollover() {
    final latest = _latestCounter;
    if (latest == null) return;
    if (_baselineDay != _dayKey(DateTime.now())) {
      unawaited(_resolveBaseline(latest));
    }
    _notify();
  }

  // ==== Tagesbeginn bestimmen ====

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool _sameBoot(int? a, int? b) => a == null || b == null || (a - b).abs() < _bootToleranceMs;

  Future<int?> _bootTimeMillis() async {
    try {
      return await _channel.invokeMethod<int>('bootTime');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _midnightSnapshot() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('midnightSnapshot');
    } catch (_) {
      return null;
    }
  }

  /// Bestimmt den Zählerstand zu Beginn des heutigen Tages. Reihenfolge:
  /// 1. Mitternachts-Snapshot (Alarm) desselben Geräte-Starts - exakt.
  /// 2. Gerät wurde heute neu gestartet - Zähler begann bei 0.
  /// 3. Sonst der Zählerstand der ersten Messung des Tages (gemerkt in
  ///    SharedPreferences) - Schritte davor fehlen.
  Future<void> _resolveBaseline(int counter) async {
    if (_baselineResolving) return;
    _baselineResolving = true;
    try {
      final now = DateTime.now();
      final day = _dayKey(now);
      final startOfToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final bootMs = await _bootTimeMillis();
      final snapshot = await _midnightSnapshot();

      int baseline;
      StepBaselineKind kind;
      final snapDay = snapshot?['day'];
      final snapCounter = (snapshot?['counter'] as num?)?.toInt();
      final snapBoot = (snapshot?['boot'] as num?)?.toInt();

      if (snapDay == day && snapCounter != null && _sameBoot(snapBoot, bootMs)) {
        baseline = snapCounter;
        kind = StepBaselineKind.midnight;
      } else if (bootMs != null && bootMs >= startOfToday) {
        baseline = 0;
        kind = StepBaselineKind.sinceBoot;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final storedDay = prefs.getString(_firstDayKey);
        final storedCounter = prefs.getInt(_firstCounterKey);
        final storedBoot = prefs.getInt(_firstBootKey);
        if (storedDay == day &&
            storedCounter != null &&
            storedCounter <= counter &&
            _sameBoot(storedBoot, bootMs)) {
          baseline = storedCounter;
        } else {
          baseline = counter;
          await prefs.setString(_firstDayKey, day);
          await prefs.setInt(_firstCounterKey, counter);
          if (bootMs != null) await prefs.setInt(_firstBootKey, bootMs);
        }
        kind = StepBaselineKind.firstReading;
      }

      _dayBaseline = baseline;
      _baselineDay = day;
      _baselineKind = kind;
      unawaited(DiagnosticLogService.instance.log(
        'Schritte: Tagesbasis $baseline (${kind.name}), Zähler jetzt $counter',
      ));
    } catch (_) {
      // Ohne Tagesbasis zeigt die Kachel "wird ermittelt".
    } finally {
      _baselineResolving = false;
      _notify();
    }
  }

  // ==== Zählung während einer Track-Aufzeichnung ====

  /// Beginnt die Zählung einer Aufzeichnung (aufgerufen von
  /// TrackRecordingService.start). Hält den Sensor bis [endSession] aktiv.
  void beginSession() {
    _sessionActive = true;
    _sessionPaused = false;
    _sessionPausedSteps = 0;
    _pauseStartCounter = null;
    // Nur gültig, wenn der Stream bereits läuft; sonst setzt der erste
    // Sensorwert den Start (siehe _onCounter).
    _sessionStart = _liveCount;
    if (!_sessionAcquired) {
      _sessionAcquired = true;
      acquire();
    }
    _notify();
  }

  /// Schritte ab jetzt nicht mehr mitzählen (manuelle Pause).
  void pauseSession() {
    if (!_sessionActive || _sessionPaused) return;
    _sessionPaused = true;
    _pauseStartCounter = _liveCount;
    _notify();
  }

  /// Zählung nach einer Pause fortsetzen - die Schritte der Pause werden
  /// herausgerechnet.
  void resumeSession() {
    if (!_sessionActive || !_sessionPaused) return;
    final live = _liveCount;
    final pauseStart = _pauseStartCounter;
    if (live != null && pauseStart != null) {
      _sessionPausedSteps += math.max(0, live - pauseStart);
    }
    _sessionPaused = false;
    _pauseStartCounter = null;
    _notify();
  }

  /// Beendet die Zählung und liefert die Schrittzahl der Aufzeichnung (null,
  /// wenn nicht gezählt werden konnte, z. B. ohne Berechtigung).
  int? endSession() {
    if (!_sessionActive) return null;
    final steps = sessionSteps;
    _sessionActive = false;
    _sessionPaused = false;
    _sessionStart = null;
    _sessionPausedSteps = 0;
    _pauseStartCounter = null;
    if (_sessionAcquired) {
      _sessionAcquired = false;
      release();
    }
    _notify();
    return steps;
  }

  void _notify() {
    if (!_updates.isClosed) _updates.add(null);
  }

  Future<void> dispose() async {
    _stopStream();
    await _updates.close();
  }
}
