import 'dart:async';
import 'dart:math' as math;

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/altitude_reading.dart';
import '../models/compass_reading.dart';
import '../services/altitude_service.dart';
import '../services/barometer_altitude_service.dart';
import '../services/compass_service.dart';
import '../util/coordinate_formatter.dart';
import 'widgets/compass_dial.dart';

/// Zeigt die aktuelle Peilung (Himmelsrichtung) des Geräts, die aktuelle
/// Höhe sowie die aktuelle Position (Breiten-/Längengrad im DMS-Format)
/// an - Letztere sofern verfügbar.
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
      _barometerAltitudeService.calibrate(
        referenceAltitudeMeters: reading.altitudeMeters,
        referenceLatitude: reading.latitude,
        referenceLongitude: reading.longitude,
        referencePositionAccuracyMeters: reading.positionAccuracyMeters,
      );
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

  /// Haupttext der Höhenanzeige (OHNE Genauigkeit - die steht jetzt in
  /// einem eigenen, deutlich kleineren Text-Widget, siehe
  /// [_altitudeAccuracyText]) - die Höhe wird als Meter über Normal-Null
  /// angegeben (übliche deutsche Bezugsgröße für Höhenangaben, Abkürzung
  /// "ü. NN"). "Höhe: nicht verfügbar", solange keine Standort-
  /// Berechtigung besteht bzw. noch kein Wert vorliegt, sonst z. B.
  /// "Höhe: 512,3 m ü. NN" bzw. ohne Barometer "Höhe: 512 m ü. NN".
  String get _altitudeText {
    final reading = _altitudeReading;
    if (reading == null) return 'Höhe: nicht verfügbar';

    final format = _usingBarometer ? _altitudeFormatBarometer : _altitudeFormatGps;
    return 'Höhe: ${format.format(reading.altitudeMeters)} m ü. NN';
  }

  /// Genauigkeit der Höhenangabe - bewusst getrennt von [_altitudeText],
  /// da sie in einem eigenen, deutlich kleineren Text-Widget erscheint
  /// (siehe build()), analog zur Genauigkeit der Kursangabe.
  String get _altitudeAccuracyText {
    final reading = _altitudeReading;
    if (reading == null || reading.altitudeAccuracyMeters == null) {
      return 'Genauigkeit: unbekannt';
    }
    final format = _usingBarometer ? _altitudeFormatBarometer : _altitudeFormatGps;
    final source = _usingBarometer ? 'Barometer' : 'GPS';
    return 'Genauigkeit: ± ${format.format(reading.altitudeAccuracyMeters!)} m ($source)';
  }

  /// Textstil für Genauigkeitsangaben (Kurs, Höhe UND Position) - zwei
  /// Drittel der Schriftgröße der jeweils zugehörigen Hauptangabe
  /// (displaySmall) - auf Wunsch etwa doppelt so groß wie die
  /// ursprüngliche Version (ein Drittel), damit die Genauigkeit besser
  /// lesbar ist, aber weiterhin klar untergeordnet und in einem eigenen
  /// Text-Widget darunter steht.
  TextStyle? _accuracyStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.displaySmall;
    final baseFontSize = base?.fontSize;
    if (base == null || baseFontSize == null) {
      return Theme.of(context).textTheme.bodySmall;
    }
    return base.copyWith(fontSize: baseFontSize * 2 / 3);
  }

  /// Breitengrad der aktuellen Position im DMS-Format (Grad/Minuten/
  /// Sekunden), z. B. "Breite: 52° 37' 12,3" N" - stammt aus derselben
  /// GPS-Messung wie die Höhe (siehe [AltitudeReading], _initializeAltitude).
  String get _latitudeText {
    final reading = _altitudeReading;
    if (reading == null) return 'Breite: nicht verfügbar';
    return 'Breite: ${CoordinateFormatter.formatLatitude(reading.latitude)}';
  }

  /// Längengrad der aktuellen Position im DMS-Format, analog zu
  /// [_latitudeText].
  String get _longitudeText {
    final reading = _altitudeReading;
    if (reading == null) return 'Länge: nicht verfügbar';
    return 'Länge: ${CoordinateFormatter.formatLongitude(reading.longitude)}';
  }

  /// Genauigkeit der aktuellen Position (horizontal, bezieht sich auf
  /// Breite/Länge GEMEINSAM - anders als bei Kurs/Höhe gibt es hier
  /// bewusst nur EINE Zeile, nicht getrennt für Breite und Länge, da ein
  /// GPS-Fix nur eine gemeinsame horizontale Genauigkeit liefert) - steht
  /// unterhalb der Positionsangabe, analog zur Genauigkeit von Kurs und
  /// Höhe.
  String get _positionAccuracyText {
    final reading = _altitudeReading;
    if (reading == null || reading.positionAccuracyMeters == null) {
      return 'Genauigkeit: unbekannt';
    }
    return 'Genauigkeit: ± ${_altitudeFormatGps.format(reading.positionAccuracyMeters!)} m';
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
    // "Kurs: " als Label direkt vor der Gradangabe - bewusst Teil
    // desselben Text-Widgets (siehe unten), damit Label und Wert
    // garantiert in exakt derselben Schriftart/-größe erscheinen.
    final headingText = 'Kurs: ${_degreeFormat.format(heading)}°';

    return SafeArea(
      // GEÄNDERT: Statt fester Größen (die auf Geräten mit großer
      // Systemschrift/-anzeige, z. B. vielen Samsung-Geräten mit
      // standardmäßig vergrößerter Schriftgröße, zu Überlappungen
      // zwischen Kompassrose und Textblock führen konnten) wird der
      // verfügbare Platz jetzt per LayoutBuilder zur Laufzeit gemessen:
      // Die Kompassrose bekommt eine anhand der tatsächlich verfügbaren
      // Höhe/Breite berechnete, garantiert passende Größe, und der
      // komplette Textblock (Kurs, Höhe, Position) wird über ein
      // FittedBox(fit: BoxFit.scaleDown) automatisch so weit verkleinert,
      // dass er IMMER in den verbleibenden Platz passt - unabhängig von
      // Bildschirmgröße oder Systemschriftgröße. Ist genug Platz
      // vorhanden, bleibt die reguläre (displaySmall-)Schriftgröße
      // erhalten; nur bei Platzmangel wird verkleinert. Kompassrose und
      // Textblock bleiben dabei an Ober- bzw. Unterkante verankert - der
      // freie Bereich dazwischen ergibt sich automatisch.
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final availableHeight = constraints.maxHeight;

            // Kompassrose: quadratisch, orientiert an der verfügbaren
            // Breite, aber auf maximal ca. 42 % der verfügbaren Höhe
            // begrenzt, damit für den Textblock darunter in jedem Fall
            // ausreichend Platz übrig bleibt.
            const minDialSize = 120.0;
            const maxDialSize = 280.0;
            final dialSize = math.min(availableWidth, availableHeight * 0.42)
                .clamp(minDialSize, maxDialSize)
                .toDouble();

            // Rest der Höhe (abzüglich eines kleinen Mindestabstands)
            // steht dem Textblock zur Verfügung - das FittedBox unten
            // sorgt dafür, dass er nie mehr als das beansprucht.
            const gap = 16.0;
            final textBlockMaxHeight =
                (availableHeight - dialSize - gap).clamp(60.0, availableHeight).toDouble();

            return Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: dialSize,
                    height: dialSize,
                    child: CompassDial(headingDegrees: heading),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: availableWidth,
                      maxHeight: textBlockMaxHeight,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
                      child: _buildTextBlock(context, headingText),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Der gesamte Textblock unterhalb der Kompassrose (Kurs, Höhe,
  /// Position samt jeweiliger Genauigkeit) - als eigene Methode
  /// ausgelagert, damit build() ihn unverändert per FittedBox skalieren
  /// kann (siehe dort). Die internen Schriftgrößen (displaySmall für die
  /// Hauptwerte, zwei Drittel davon für die Genauigkeitsangaben, siehe
  /// [_accuracyStyle]) bleiben untereinander im selben Verhältnis, auch
  /// wenn das FittedBox den gesamten Block bei Platzmangel gleichmäßig
  /// verkleinert.
  Widget _buildTextBlock(BuildContext context, String headingText) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AutoHyphenatingText(
          headingText,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 4),
        // Eigenes, deutlich kleineres Text-Widget (ein Drittel der
        // Schriftgröße der Kursangabe) statt gleich groß.
        AutoHyphenatingText(
          _reading?.accuracyDegrees != null
              ? 'Genauigkeit: ± ${_degreeFormat.format(_reading!.accuracyDegrees!)}°'
              : 'Genauigkeit: unbekannt',
          style: _accuracyStyle(context),
        ),
        const SizedBox(height: 8),
        // Bewusst dieselbe Schriftart/-größe wie die Kursangabe oben
        // (displaySmall) - die zugehörige Genauigkeit steht separat
        // darunter, NICHT im selben Text enthalten.
        AutoHyphenatingText(
          _altitudeText,
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        // Eigenes, deutlich kleineres Text-Widget (ein Drittel der
        // Schriftgröße der Höhenangabe) - analog zur Kurs-Genauigkeit
        // oben.
        AutoHyphenatingText(
          _altitudeAccuracyText,
          style: _accuracyStyle(context),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // Aktuelle Position im DMS-Format - Breite und Länge JEWEILS in
        // einer eigenen Zeile und in derselben Schriftgröße wie die
        // Kursangabe (displaySmall).
        AutoHyphenatingText(
          _latitudeText,
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        AutoHyphenatingText(
          _longitudeText,
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        // Genauigkeit der Position - eine einzelne Zeile für Breite UND
        // Länge gemeinsam (siehe _positionAccuracyText), analog zur
        // Genauigkeit von Kurs und Höhe.
        AutoHyphenatingText(
          _positionAccuracyText,
          style: _accuracyStyle(context),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
