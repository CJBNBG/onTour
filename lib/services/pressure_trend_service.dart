import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/pressure_reading.dart';

class _PressureSample {
  final DateTime time;
  final double hPa;

  /// Zuletzt bekannte Höhe (m) zum Zeitpunkt der Probe - nur zur
  /// Erkennung von Höhenänderungen, null wenn keine aktuelle Höhe vorlag.
  final double? altitudeMeters;

  const _PressureSample(this.time, this.hPa, this.altitudeMeters);

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'p': hPa,
        'a': altitudeMeters,
      };

  factory _PressureSample.fromJson(Map<String, dynamic> json) => _PressureSample(
        DateTime.parse(json['t'] as String),
        (json['p'] as num).toDouble(),
        (json['a'] as num?)?.toDouble(),
      );
}

/// Verfolgt den Luftdruck über mehrere Stunden und leitet daraus einen
/// 3-Stunden-Trend ab (siehe README Abschnitt 47) - ein schneller
/// Druckabfall ist besonders für Segler ein wichtiges Warnsignal.
///
/// WICHTIG (bewusste Architektur-Ausnahme, analog zu
/// TrackRecordingService): Diese Instanz lebt einmalig in HomeShell und
/// NICHT pro Seitenaufruf - ein Trend braucht den Verlauf über Stunden,
/// der bei jedem Seitenwechsel verloren ginge. Zusätzlich wird der
/// Verlauf periodisch als Datei gesichert und beim nächsten Start wieder
/// geladen, damit auch ein App-Neustart den Trend nicht zurücksetzt.
///
/// Funktionsweise: Der Sensor wird fortlaufend gelesen, der Druck über
/// jeweils eine Minute gemittelt (eine Probe pro Minute, Verlauf max.
/// 4 Stunden). Der Trend ist die Steigung einer Ausgleichsgeraden
/// (lineare Regression) über das 3-Stunden-Fenster, hochgerechnet auf
/// hPa pro 3 Stunden - robuster gegen Rauschen und Lücken als die bloße
/// Differenz zweier Messwerte.
///
/// EINSCHRÄNKUNGEN: (1) Im Hintergrund liefert Android Sensorwerte nicht
/// garantiert - der Verlauf kann Lücken haben (die Regression kommt damit
/// zurecht, bei < 30 min Verlauf gibt es noch keinen Trend). (2) Ändert
/// sich die Höhe, ändert sich der Druck um rund 1,2 hPa pro 10 m - das
/// lässt sich vom Wetter nicht trennen. Über [noteAltitude] gemeldete
/// Höhen dienen daher nur dazu, eine Höhenänderung > 15 m im Fenster zu
/// erkennen und den Trend als unsicher zu markieren.
class PressureTrendService {
  static const _fileName = 'ontour_pressure_history.json';
  static const Duration _sampleInterval = Duration(minutes: 1);
  static const Duration _historySpan = Duration(hours: 4);
  static const Duration _trendWindow = Duration(hours: 3);
  static const Duration _saveInterval = Duration(minutes: 5);
  static const Duration _altitudeMaxAge = Duration(minutes: 5);
  static const double _altitudeSpreadLimitMeters = 15;

  /// Mindest-Verlauf, ab dem ein Trend angezeigt wird.
  static const Duration minTrendBasis = Duration(minutes: 30);

  /// Plausibler Bereich für Stationsdruck (inkl. Hochgebirge) - Werte
  /// außerhalb werden als Sensorfehler verworfen.
  static const double _minPlausibleHPa = 400;
  static const double _maxPlausibleHPa = 1100;

  /// Glättung der Live-Anzeige (EMA) - die Proben für den Verlauf werden
  /// unabhängig davon über jeweils eine Minute gemittelt.
  static const double _displayAlpha = 0.2;

  final List<_PressureSample> _samples = [];
  final StreamController<void> _updatesController = StreamController<void>.broadcast();
  StreamSubscription<BarometerEvent>? _subscription;

  double? _displayHPa;
  double _windowSum = 0;
  int _windowCount = 0;
  DateTime? _windowStart;
  DateTime? _lastSavedAt;

  double? _lastAltitude;
  DateTime? _lastAltitudeAt;

  PressureReading? _current;

  /// Aktueller Wert - null, solange noch keine Barometer-Messung
  /// eingetroffen ist (oder das Gerät keinen Drucksensor besitzt).
  PressureReading? get current => _current;

  /// Feuert bei jedem neuen Messwert.
  Stream<void> get updates => _updatesController.stream;

  /// Wird von Seiten gemeldet, die eine aktuelle Höhe kennen (derzeit
  /// CompassPage) - nur zur Erkennung von Höhenänderungen, siehe
  /// Klassenkommentar.
  void noteAltitude(double meters) {
    _lastAltitude = meters;
    _lastAltitudeAt = DateTime.now();
  }

  Future<void> start() async {
    if (_subscription != null) return;
    await _load();
    _windowStart = DateTime.now();
    _subscription = barometerEventStream(samplingPeriod: const Duration(seconds: 2)).listen(
      _onBarometer,
      // Gerät ohne Barometer: einfach keine Werte, keine Anzeige.
      onError: (Object error) {},
    );
  }

  void _onBarometer(BarometerEvent event) {
    final p = event.pressure;
    if (!p.isFinite || p < _minPlausibleHPa || p > _maxPlausibleHPa) return;

    final now = DateTime.now();
    final previous = _displayHPa;
    _displayHPa = previous == null ? p : previous + _displayAlpha * (p - previous);

    _windowSum += p;
    _windowCount++;
    final start = _windowStart ??= now;
    if (now.difference(start) >= _sampleInterval && _windowCount > 0) {
      _samples.add(_PressureSample(now, _windowSum / _windowCount, _recentAltitude(now)));
      _windowSum = 0;
      _windowCount = 0;
      _windowStart = now;
      _prune(now);
      _maybeSave(now);
    }

    _current = _buildReading(now);
    _updatesController.add(null);
  }

  double? _recentAltitude(DateTime now) {
    final at = _lastAltitudeAt;
    if (at == null || now.difference(at) > _altitudeMaxAge) return null;
    return _lastAltitude;
  }

  void _prune(DateTime now) {
    _samples.removeWhere((s) => now.difference(s.time) > _historySpan);
  }

  PressureReading? _buildReading(DateTime now) {
    final display = _displayHPa;
    if (display == null) return null;

    // Proben im Trend-Fenster plus der aktuelle Wert als letzter Punkt.
    final windowSamples =
        _samples.where((s) => now.difference(s.time) <= _trendWindow).toList();
    final points = <_PressureSample>[
      ...windowSamples,
      _PressureSample(now, display, null),
    ];

    final basis = points.last.time.difference(points.first.time);
    double? change;
    Duration? usedBasis;
    if (points.length >= 2 && basis >= minTrendBasis) {
      change = _slopePer3h(points);
      if (change != null) usedBasis = basis;
    }

    final altitudes = windowSamples.map((s) => s.altitudeMeters).whereType<double>().toList();
    final altitudeChanged = altitudes.length >= 2 &&
        (altitudes.reduce(math.max) - altitudes.reduce(math.min)) > _altitudeSpreadLimitMeters;

    return PressureReading(
      hPa: display,
      changePer3hHPa: change,
      trendBasis: usedBasis,
      altitudeChanged: altitudeChanged,
    );
  }

  /// Steigung der Ausgleichsgeraden (Druck über Zeit), hochgerechnet auf
  /// hPa pro 3 Stunden.
  static double? _slopePer3h(List<_PressureSample> points) {
    final t0 = points.first.time;
    final xs = [for (final p in points) p.time.difference(t0).inSeconds / 3600.0];
    final ys = [for (final p in points) p.hPa];
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < xs.length; i++) {
      numerator += (xs[i] - meanX) * (ys[i] - meanY);
      denominator += (xs[i] - meanX) * (xs[i] - meanX);
    }
    if (denominator <= 0) return null;
    return numerator / denominator * 3;
  }

  // ==== Persistenz ====

  Future<File> _file() async {
    final documents = await getApplicationDocumentsDirectory();
    return File('${documents.path}/$_fileName');
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List;
      final now = DateTime.now();
      final loaded = [
        for (final e in list) _PressureSample.fromJson(e as Map<String, dynamic>),
      ]
        ..removeWhere((s) => now.difference(s.time) > _historySpan || s.time.isAfter(now))
        ..sort((a, b) => a.time.compareTo(b.time));
      _samples
        ..clear()
        ..addAll(loaded);
    } catch (_) {
      // Beschädigter Verlauf - einfach ohne Verlauf neu beginnen.
    }
  }

  void _maybeSave(DateTime now) {
    final last = _lastSavedAt;
    if (last != null && now.difference(last) < _saveInterval) return;
    _lastSavedAt = now;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode([for (final s in _samples) s.toJson()]));
    } catch (_) {
      // Reiner Komfort-Zusatz - ein fehlgeschlagener Schreibversuch darf
      // die Messung nicht beeinträchtigen.
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _save();
    await _updatesController.close();
  }
}
