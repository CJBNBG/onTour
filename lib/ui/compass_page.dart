import 'dart:async';
import 'dart:math' as math;

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/altitude_reading.dart';
import '../models/compass_reading.dart';
import '../models/position_display_format.dart';
import '../models/speed_accuracy_mode.dart';
import '../services/altitude_service.dart';
import '../services/app_preferences.dart';
import '../services/barometer_altitude_service.dart';
import '../services/compass_service.dart';
import '../services/pressure_trend_service.dart';
import '../util/coordinate_formatter.dart';
import 'compass_calibration_page.dart';
import 'widgets/accuracy_badge.dart';
import 'widgets/compass_dial.dart';
import 'widgets/measurement_pulse_indicator.dart';
import 'widgets/accuracy_text_style.dart';

/// Zeigt die aktuelle Peilung (Himmelsrichtung) des Geräts, die aktuelle
/// Höhe sowie die aktuelle Position an - Letztere in einem der vier
/// wählbaren Formate (DMS/DMM/DD/UTM, siehe README Abschnitt 25,
/// [PositionDisplayFormat]), sofern verfügbar.
///
/// NEU (siehe README Abschnitt 39): Die Peilung kommt aus einer
/// Gyro-Fusion (siehe CompassService) und ist dadurch ruhiger. Bei
/// unplausiblem Magnetfeld erscheint in der Statuszeile der Chip
/// "Kompass gestört" samt Hinweisdialog.
class CompassPage extends StatefulWidget {
  final AppPreferences preferences;

  /// NEU (README Abschnitt 47): Von HomeShell gehaltener Luftdruck-Verlauf
  /// (lebt länger als diese Seite, siehe PressureTrendService).
  final PressureTrendService pressureService;

  const CompassPage({super.key, required this.preferences, required this.pressureService});

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
  StreamSubscription<void>? _pressureSubscription;
  CompassReading? _reading;
  AltitudeReading? _altitudeReading;

  /// true, sobald mindestens eine barometrisch (gegen GPS kalibrierte)
  /// Höhenmessung vorliegt - die Anzeige wechselt dann von der groben
  /// GPS-Höhe auf die deutlich präzisere Barometer-Höhe (siehe
  /// BarometerAltitudeService für die Hintergründe).
  bool _usingBarometer = false;

  /// Siehe README Abschnitt 37: Wird bei jeder neuen GPS- ODER
  /// Barometer-Höhenmessung erhöht - dient MeasurementPulseIndicator als
  /// Auslöser für den kurzen optischen Impuls. Bewusst NICHT bei jedem
  /// Kompass-Update erhöht.
  int _measurementTick = 0;

  /// Position, fuer die zuletzt die Deklination ermittelt wurde.
  double? _declinationLat;
  double? _declinationLon;
  static const _declinationRefreshDegrees = 0.25;

  void _maybeUpdateDeclination(AltitudeReading reading) {
    final lat = _declinationLat;
    final lon = _declinationLon;
    final needsUpdate = lat == null || lon == null || (reading.latitude - lat).abs() > _declinationRefreshDegrees || (reading.longitude - lon).abs() > _declinationRefreshDegrees;
    if (!needsUpdate) return;
    _declinationLat = reading.latitude;
    _declinationLon = reading.longitude;
    unawaited(_compassService.updateDeclination(
      latitude: reading.latitude,
      longitude: reading.longitude,
      altitude: reading.altitudeMeters,
    ));
  }

  static final NumberFormat _degreeFormat = NumberFormat('0', 'de_DE');
  static final NumberFormat _altitudeFormatGps = NumberFormat('0', 'de_DE');
  static final NumberFormat _altitudeFormatBarometer = NumberFormat('0.0', 'de_DE');
  static final NumberFormat _pressureFormat = NumberFormat('0.0', 'de_DE');

  /// Mit explizitem Vorzeichen (+/-) für die Druckänderung.
  static final NumberFormat _pressureChangeFormat = NumberFormat('+0.0;-0.0', 'de_DE');

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
    // NEU (README Abschnitt 47): Der Verlauf selbst läuft in HomeShell
    // weiter - diese Seite zeigt nur den aktuellen Stand an.
    _pressureSubscription = widget.pressureService.updates.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
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
      _maybeUpdateDeclination(reading);
      widget.pressureService.noteAltitude(reading.altitudeMeters);
      if (_usingBarometer) return; // Barometer-Wert hat weiterhin Vorrang
      setState(() {
        _altitudeReading = reading;
        _measurementTick++;
      });
    });

    // Barometer-Höhe: liefert erst Werte, sobald oben mindestens einmal
    // kalibriert wurde - ersetzt die GPS-Anzeige dann durch die deutlich
    // präzisere, rauschärmere Barometer-Höhe.
    _barometerAltitudeSubscription = _barometerAltitudeService.altitudeStream().listen(
      (reading) {
        if (!mounted) return;
        widget.pressureService.noteAltitude(reading.altitudeMeters);
        setState(() {
          _altitudeReading = reading;
          _usingBarometer = true;
          _measurementTick++;
        });
      },
      // Siehe README Abschnitt 27: Ohne expliziten Handler würde ein vom
      // Sensor gemeldeter Fehler (z. B. Gerät ohne Barometer) als
      // unbehandelter Stream-Fehler durchschlagen. In diesem Fall bleibt
      // es einfach bei der GPS-Höhe.
      onError: (Object error) {},
    );
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _gpsAltitudeSubscription?.cancel();
    _barometerAltitudeSubscription?.cancel();
    _pressureSubscription?.cancel();
    // NEU (README Abschnitt 39): CompassService hält jetzt mehrere
    // Sensor-Subscriptions (Gyro, Beschleunigung, Magnetometer) und
    // einen Controller und muss deshalb freigegeben werden.
    unawaited(_compassService.dispose());
    unawaited(_altitudeService.dispose());
    unawaited(_barometerAltitudeService.dispose());
    WakelockPlus.disable();
    super.dispose();
  }

  /// Haupttext der Höhenanzeige (OHNE Genauigkeit - die steht in einem
  /// eigenen, kleineren Text-Widget, siehe [_altitudeAccuracyText]) - die
  /// Höhe wird als Meter über Normal-Null angegeben (Abkürzung "ü. NN").
  /// "Höhe: nicht verfügbar", solange keine Standort-Berechtigung besteht
  /// bzw. noch kein Wert vorliegt, sonst z. B. "Höhe: 512,3 m ü. NN"
  /// bzw. ohne Barometer "Höhe: 512 m ü. NN".
  String get _altitudeText {
    final reading = _altitudeReading;
    if (reading == null) return 'Höhe: nicht verfügbar';

    final format = _usingBarometer ? _altitudeFormatBarometer : _altitudeFormatGps;
    return 'Höhe: ${format.format(reading.altitudeMeters)} m ü. NN';
  }

  /// Genauigkeit der Höhenangabe - bewusst getrennt von [_altitudeText],
  /// da sie in einem eigenen, kleineren Text-Widget erscheint (siehe
  /// build()), analog zur Genauigkeit der Kursangabe.
  String get _altitudeAccuracyText {
    final reading = _altitudeReading;
    if (reading == null || reading.altitudeAccuracyMeters == null) {
      return 'Genauigkeit: unbekannt';
    }
    final format = _usingBarometer ? _altitudeFormatBarometer : _altitudeFormatGps;
    final source = _usingBarometer ? 'Barometer' : 'GPS';
    return 'Genauigkeit: ± ${format.format(reading.altitudeAccuracyMeters!)} m ($source)';
  }

  /// NEU (README Abschnitt 39): Genauigkeitszeile der Kursangabe - bei
  /// gestörtem Magnetfeld "gestört" statt eines (dann nicht mehr
  /// aussagekräftigen) Sensor-Genauigkeitswerts.
  String get _headingAccuracyText {
    final reading = _reading;
    if (reading?.isDisturbed == true) return 'Genauigkeit: gestört';
    if (reading?.accuracyDegrees != null) {
      return 'Genauigkeit: ± ${_degreeFormat.format(reading!.accuracyDegrees!)}°';
    }
    return 'Genauigkeit: unbekannt';
  }

  /// NEU (README Abschnitt 47): Hauptzeile der Luftdruckanzeige - der am
  /// Gerät GEMESSENE Druck (Stationsdruck), nicht der auf Meereshöhe
  /// umgerechnete Druck aus Wetterberichten. "nicht verfügbar", solange
  /// noch kein Messwert vorliegt bzw. das Gerät kein Barometer besitzt.
  String get _pressureText {
    final reading = widget.pressureService.current;
    if (reading == null) return 'Luftdruck: nicht verfügbar';
    return 'Luftdruck: ${_pressureFormat.format(reading.hPa)} hPa';
  }

  /// Trendzeile unter dem Luftdruck (3-Stunden-Tendenz, siehe
  /// PressureTrendService) - bewusst im kleineren Genauigkeits-Stil.
  String get _pressureTrendText {
    final reading = widget.pressureService.current;
    if (reading == null) return 'Trend: unbekannt';
    final category = reading.category;
    final change = reading.changePer3hHPa;
    if (category == null || change == null) return 'Trend: sammle Daten …';
    return '${category.arrow} ${category.label}: '
        '${_pressureChangeFormat.format(change)} hPa / 3 h';
  }

  /// Zusatzhinweis zum Trend - nur wenn nötig (Verlauf kürzer als 3
  /// Stunden bzw. Höhenänderung im Fenster), sonst null (keine Zeile).
  String? get _pressureTrendNote {
    final reading = widget.pressureService.current;
    if (reading == null || reading.changePer3hHPa == null) return null;
    final notes = <String>[];
    final basis = reading.trendBasis;
    if (basis != null && basis < const Duration(hours: 2, minutes: 45)) {
      notes.add('Basis: ${basis.inMinutes} min');
    }
    if (reading.altitudeChanged) {
      notes.add('Höhe geändert - Trend unsicher');
    }
    return notes.isEmpty ? null : notes.join(' · ');
  }

  /// Textstil für Genauigkeitsangaben (Kurs, Höhe UND Position) - zwei
  /// Drittel der Schriftgröße der jeweils zugehörigen Hauptangabe
  /// (displaySmall), klar untergeordnet, aber gut lesbar.
  // TextStyle? _accuracyStyle(BuildContext context) {
  //   final base = Theme.of(context).textTheme.displaySmall;
  //   final baseFontSize = base?.fontSize;
  //   if (base == null || baseFontSize == null) {
  //     return Theme.of(context).textTheme.bodySmall;
  //   }
  //   return base.copyWith(fontSize: baseFontSize * 2 / 3);
  // }
  TextStyle? _accuracyStyle(BuildContext context) => accuracyTextStyle(context);

  /// Positionszeilen im aktuell gewählten Format (siehe README Abschnitt
  /// 25, [PositionDisplayFormat]) - GENAU EINE Zeile bei UTM, sonst ZWEI
  /// Zeilen (Breite, dann Länge). Der Fallback-Text ohne vorliegende
  /// Messung passt sich derselben Zeilenanzahl an, damit der Textblock
  /// nicht "springt", sobald der erste GPS-Fix eintrifft.
  List<String> get _positionLines {
    final reading = _altitudeReading;
    final format = widget.preferences.positionDisplayFormat;
    if (reading == null) {
      return format == PositionDisplayFormat.utm ? const ['Position: nicht verfügbar'] : const ['Breite: nicht verfügbar', 'Länge: nicht verfügbar'];
    }
    return CoordinateFormatter.formatPosition(reading.latitude, reading.longitude, format);
  }

  /// Genauigkeit der aktuellen Position (horizontal, bezieht sich auf
  /// Breite/Länge GEMEINSAM) - steht unterhalb der Positionsangabe.
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
    // desselben Text-Widgets, damit Label und Wert garantiert in exakt
    // derselben Schriftart/-größe erscheinen.
    final headingText = 'Kurs: ${_degreeFormat.format(heading)}°';

    // README Abschnitt 25: ListenableBuilder sorgt dafür, dass ein
    // Wechsel des Positionsformats in den Einstellungen SOFORT sichtbar
    // wird.
    return ListenableBuilder(
      listenable: widget.preferences,
      builder: (context, _) => _buildBody(context, heading, headingText),
    );
  }

  Widget _buildBody(BuildContext context, double heading, String headingText) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // README Abschnitt 37: Zeigt die auf dieser Seite AKTUELL
            // verwendete Genauigkeitsstufe (fest die von AltitudeService
            // verwendete) sowie einen kurzen optischen Impuls bei jeder
            // neuen Höhenmessung. NEU (Abschnitt 39): in der Mitte der
            // Chip "Kompass gestört", solange das Magnetfeld unplausibel
            // ist.
            _buildStatusRow(context),
            const SizedBox(height: 12),
            Expanded(
              // Größenadaptives Layout (README Abschnitt 10/28): Der
              // verfügbare Platz wird per LayoutBuilder zur Laufzeit
              // gemessen, die Kompassrose bekommt eine daraus berechnete,
              // garantiert passende Größe, und der komplette Textblock
              // wird über FittedBox(scaleDown) so weit verkleinert, dass
              // er IMMER in den verbleibenden Platz passt.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final availableHeight = constraints.maxHeight;

                  // Kompassrose: quadratisch, max. 80 % der verfügbaren
                  // Breite und ca. 48 % der verfügbaren Höhe (README
                  // Abschnitt 28).
                  const minDialSize = 120.0;
                  const maxDialSize = 360.0;
                  const maxWidthFraction = 0.8;
                  final dialSize = math.min(availableWidth * maxWidthFraction, availableHeight * 0.48).clamp(minDialSize, maxDialSize).toDouble();

                  // Rest der Höhe (abzüglich eines kleinen Mindestabstands)
                  // steht dem Textblock zur Verfügung.
                  const gap = 16.0;
                  final textBlockMaxHeight = (availableHeight - dialSize - gap).clamp(60.0, availableHeight).toDouble();

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
          ],
        ),
      ),
    );
  }

  /// Statuszeile: Genauigkeits-Badge links, Mess-Impuls rechts, in der
  /// Mitte (nur bei Störung) der Warn-Chip. Die feste Höhe verhindert,
  /// dass das Layout beim Ein-/Ausblenden des Chips springt.
  Widget _buildStatusRow(BuildContext context) {
    final disturbed = _reading?.isDisturbed ?? false;
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AccuracyBadge(
            mode: SpeedAccuracyMode.fromLocationAccuracy(AltitudeService.fixedAccuracy),
          ),
          if (disturbed)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildDisturbanceChip(context),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // NEU (README Abschnitt 48): Immer erreichbar, nicht nur bei
              // Störung - öffnet die geführte Kalibrierung.
              IconButton(
                tooltip: 'Kompass kalibrieren',
                icon: const Icon(Icons.threesixty),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: _openCalibration,
              ),
              const SizedBox(width: 8),
              MeasurementPulseIndicator(pulseKey: _measurementTick),
            ],
          ),
        ],
      ),
    );
  }

  /// NEU (README Abschnitt 39): Antippbarer Warn-Chip bei gestörtem
  /// Magnetfeld - öffnet die geführte Kalibrierung ([_openCalibration]).
  Widget _buildDisturbanceChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _openCalibration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: scheme.onErrorContainer),
              const SizedBox(width: 6),
              // Bewusst normales Text-Widget statt AutoHyphenatingText -
              // kurzes, einzeiliges Label in beengtem Layout (siehe
              // README Abschnitt 13/24/26).
              Flexible(
                child: Text(
                  'Kompass gestört',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// NEU (README Abschnitt 48): Öffnet die geführte Kalibrierung (ersetzt
  /// den früheren reinen Hinweisdialog zur Störung, siehe Abschnitt 46) -
  /// erreichbar über den Warn-Chip UND den Kalibrier-Button der
  /// Statuszeile. Die Seite nutzt den bereits laufenden [CompassService]
  /// dieser Seite mit.
  void _openCalibration() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompassCalibrationPage(compassService: _compassService),
      ),
    );
  }

  /// Der gesamte Textblock unterhalb der Kompassrose (Kurs, Höhe,
  /// Position samt jeweiliger Genauigkeit) - als eigene Methode
  /// ausgelagert, damit build() ihn unverändert per FittedBox skalieren
  /// kann. Die internen Schriftgrößen (displaySmall für die Hauptwerte,
  /// zwei Drittel davon für die Genauigkeitsangaben) bleiben auch bei
  /// Verkleinerung durch das FittedBox im selben Verhältnis.
  Widget _buildTextBlock(BuildContext context, String headingText) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AutoHyphenatingText(
          headingText,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 4),
        // Eigenes, kleineres Text-Widget; bei gestörtem Magnetfeld
        // "gestört" (siehe _headingAccuracyText).
        AutoHyphenatingText(
          _headingAccuracyText,
          style: _accuracyStyle(context),
        ),
        const SizedBox(height: 8),
        // Dieselbe Schriftart/-größe wie die Kursangabe oben
        // (displaySmall) - die zugehörige Genauigkeit steht separat
        // darunter.
        AutoHyphenatingText(
          _altitudeText,
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        AutoHyphenatingText(
          _altitudeAccuracyText,
          style: _accuracyStyle(context),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // NEU (README Abschnitt 47): Luftdruck (Stationsdruck) samt
        // 3-Stunden-Trend - dieselbe Schriftgröße wie Kurs/Höhe, der
        // Trend darunter im kleineren Genauigkeits-Stil.
        AutoHyphenatingText(
          _pressureText,
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        AutoHyphenatingText(
          _pressureTrendText,
          style: _accuracyStyle(context),
          textAlign: TextAlign.center,
        ),
        if (_pressureTrendNote != null)
          AutoHyphenatingText(
            _pressureTrendNote!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 8),
        // README Abschnitt 25: Positionszeile(n) im gewählten Format -
        // ZWEI Zeilen (Breite, Länge) bei DMS/DMM/DD, EINE gemeinsame
        // Zeile bei UTM (siehe _positionLines).
        for (final line in _positionLines) ...[
          AutoHyphenatingText(
            line,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
        ],
        // Genauigkeit der Position - eine Zeile für Breite UND Länge
        // gemeinsam, gilt für ALLE vier Formate.
        AutoHyphenatingText(
          _positionAccuracyText,
          style: _accuracyStyle(context),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
