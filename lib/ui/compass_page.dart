import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/altitude_reading.dart';
import '../models/compass_reading.dart';
import '../services/altitude_service.dart';
import '../services/barometer_altitude_service.dart';
import '../services/compass_service.dart';
import 'widgets/compass_dial.dart';

/// Zeigt die aktuelle Peilung (Himmelsrichtung) des Geräts sowie - sofern
/// verfügbar - die aktuelle Höhe an.
class CompassPage extends StatefulWidget {
  const CompassPage({super.key});

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> {
  final CompassService _compassService = CompassService();
  final AltitudeService _altitudeService = AltitudeService();
  final BarometerAltitudeService _barometerAltitudeService = BarometerAltitudeService();
  StreamSubscription<CompassReading>? _compassSubscription;
  StreamSubscription<AltitudeReading>? _gpsAltitudeSubscription;
  StreamSubscription<AltitudeReading>? _barometerAltitudeSubscription;
  CompassReading? _reading;
  AltitudeReading? _altitudeReading;

  /// true, sobald mindestens eine barometrisch (gegen GPS kalibrierte)
  /// Höhenmessung vorliegt - die Anzeige wechselt dann von der groben
  /// GPS-Höhe auf die deutlich präzisere Barometer-Höhe (siehe
  /// BarometerAltitudeService für die Hintergründe).
  bool _usingBarometer = false;

  static final NumberFormat _degreeFormat = NumberFormat('0', 'de_DE');
  static final NumberFormat _altitudeFormatGps = NumberFormat('0', 'de_DE');
  static final NumberFormat _altitudeFormatBarometer = NumberFormat('0.0', 'de_DE');

  @override
  void initState() {
    super.initState();
    // Bildschirm bleibt an, solange die Kompassseite sichtbar ist - analog
    // zur Tacho-Seite (siehe dort für die Begründung).
    WakelockPlus.enable();
    if (_compassService.isSupported) {
      _compassSubscription = _compassService.readingStream().listen((reading) {
        if (!mounted) return;
        setState(() => _reading = reading);
      });
    }
    _initializeAltitude();
  }

  Future<void> _initializeAltitude() async {
    final granted = await _altitudeService.hasPermission();
    if (!granted || !mounted) return;

    // GPS-Höhe: dient sowohl als Anzeige-Fallback (falls kein Barometer
    // vorhanden ist) als auch als fortlaufende Referenz, gegen die der
    // Barometer kalibriert wird (siehe BarometerAltitudeService).
    _gpsAltitudeSubscription = _altitudeService.altitudeStream().listen((reading) {
      if (!mounted) return;
      _barometerAltitudeService.calibrate(referenceAltitudeMeters: reading.altitudeMeters);
      if (_usingBarometer) return; // Barometer-Wert hat weiterhin Vorrang
      setState(() => _altitudeReading = reading);
    });

    // Barometer-Höhe: liefert erst Werte, sobald oben mindestens einmal
    // kalibriert wurde - ersetzt die GPS-Anzeige dann durch die deutlich
    // präzisere, rauschärmere Barometer-Höhe.
    _barometerAltitudeSubscription =
        _barometerAltitudeService.altitudeStream().listen((reading) {
      if (!mounted) return;
      setState(() {
        _altitudeReading = reading;
        _usingBarometer = true;
      });
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _gpsAltitudeSubscription?.cancel();
    _barometerAltitudeSubscription?.cancel();
    unawaited(_altitudeService.dispose());
    unawaited(_barometerAltitudeService.dispose());
    WakelockPlus.disable();
    super.dispose();
  }

  /// Formatierter Höhentext inkl. Genauigkeit und Quelle -
  /// "Höhe: nicht verfügbar", solange keine Standort-Berechtigung besteht
  /// bzw. noch kein Wert vorliegt, sonst z. B.
  /// "Höhe: 512,3 m (± 0,3 m, Barometer)" bzw. ohne Barometer
  /// "Höhe: 512 m (± 8 m, GPS)".
  String get _altitudeText {
    final reading = _altitudeReading;
    if (reading == null) return 'Höhe: nicht verfügbar';

    final format = _usingBarometer ? _altitudeFormatBarometer : _altitudeFormatGps;
    final altitude = '${format.format(reading.altitudeMeters)} m';
    final accuracy = reading.altitudeAccuracyMeters != null
        ? ' (± ${format.format(reading.altitudeAccuracyMeters!)} m'
              '${_usingBarometer ? ', Barometer' : ', GPS'})'
        : '';
    return 'Höhe: $altitude$accuracy';
  }

  @override
  Widget build(BuildContext context) {
    if (!_compassService.isSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_off, size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              AutoHyphenatingText(
                'Dieses Gerät verfügt über keinen Kompass-Sensor.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final heading = _reading?.headingDegrees ?? 0;
    final headingText = '${_degreeFormat.format(heading)}°';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CompassDial(headingDegrees: heading),
                ),
              ),
            ),
            AutoHyphenatingText(
              headingText,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              _reading?.accuracyDegrees != null
                  ? 'Genauigkeit: ± ${_degreeFormat.format(_reading!.accuracyDegrees!)}°'
                  : 'Genauigkeit: unbekannt',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            AutoHyphenatingText(
              _altitudeText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
