import 'dart:async';
import 'dart:math' as math;

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/altitude_reading.dart';
import '../models/compass_reading.dart';
import '../models/speed_accuracy_mode.dart';
import '../services/altitude_correction.dart';
import '../services/altitude_service.dart';
import '../services/app_preferences.dart';
import '../services/barometer_altitude_service.dart';
import '../services/compass_service.dart';
import '../services/pressure_trend_service.dart';
import 'compass_calibration_page.dart';
import 'widgets/accuracy_badge.dart';
import 'widgets/compass_dial.dart';
import 'widgets/measurement_pulse_indicator.dart';
import 'widgets/accuracy_text_style.dart';

/// Zeigt die aktuelle Peilung (Himmelsrichtung) des Geräts als große
/// Kompassrose samt Kursangabe.
///
/// NEU (README Abschnitt 58): Höhe, Luftdruck und Position stehen nicht mehr
/// hier, sondern auf der Start-Seite (Abschnitt 56) - dadurch bekommt die
/// Kompassrose fast den gesamten Platz der Seite. Die dafür nötigen Dienste
/// (GPS-Höhe, Barometer) laufen hier weiter: Sie liefern den Standort für
/// die Missweisung (Kurs auf geografisch Nord, Abschnitt 41) und die
/// gemeldete Höhe an den Luftdruck-Trend (Abschnitt 47). Die
/// Höhenkalibrierung (Abschnitt 54) liegt seit Abschnitt 61 in der
/// Höhen-Kachel der Start-Seite.
///
/// Die Peilung kommt aus einer Gyro-Fusion (siehe CompassService, Abschnitt
/// 46); bei unplausiblem Magnetfeld erscheint in der Statuszeile der Chip
/// "Kompass gestört", Antippen öffnet die geführte Kalibrierung (Abschnitt
/// 48).
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
    // Nach der Ermittlung neu zeichnen, damit die Missweisung in der
    // Anzeige erscheint (siehe [_declinationText]).
    unawaited(_compassService
        .updateDeclination(
          latitude: reading.latitude,
          longitude: reading.longitude,
          altitude: reading.altitudeMeters,
        )
        .then((_) {
      if (mounted) setState(() {});
    }));
  }

  static final NumberFormat _degreeFormat = NumberFormat('0', 'de_DE');
  static final NumberFormat _declinationFormat = NumberFormat('0.0', 'de_DE');

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
      // NEU (README Abschnitt 54): NN-Korrektur auf die GPS-Höhe, manueller
      // Versatz nur auf den angezeigten Endwert.
      final correction = AltitudeCorrection.instance;
      unawaited(correction.refreshIfDue(
        dartAltitude: reading.altitudeMeters,
        shownAltitude: _altitudeReading?.altitudeMeters,
      ));
      final reference = correction.gpsReference(reading.altitudeMeters);
      final shown = _withAltitude(reading, correction.display(reference));
      _barometerAltitudeService.calibrate(
        referenceAltitudeMeters: reference,
        referenceLatitude: reading.latitude,
        referenceLongitude: reading.longitude,
        referencePositionAccuracyMeters: reading.positionAccuracyMeters,
        referenceAltitudeAccuracyMeters: reading.altitudeAccuracyMeters,
      );
      _maybeUpdateDeclination(reading);
      widget.pressureService.noteAltitude(shown.altitudeMeters);
      if (_usingBarometer) return; // Barometer-Wert hat weiterhin Vorrang
      setState(() {
        _altitudeReading = shown;
        _measurementTick++;
      });
    });

    // Barometer-Höhe: liefert erst Werte, sobald oben mindestens einmal
    // kalibriert wurde - ersetzt die GPS-Anzeige dann durch die deutlich
    // präzisere, rauschärmere Barometer-Höhe.
    _barometerAltitudeSubscription = _barometerAltitudeService.altitudeStream().listen(
      (reading) {
        if (!mounted) return;
        final shown = _withAltitude(
          reading,
          AltitudeCorrection.instance.display(reading.altitudeMeters),
        );
        widget.pressureService.noteAltitude(shown.altitudeMeters);
        setState(() {
          _altitudeReading = shown;
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

  /// Kopie einer Messung mit anderem Höhenwert (Position etc. bleiben).
  AltitudeReading _withAltitude(AltitudeReading r, double altitude) => AltitudeReading(
        altitudeMeters: altitude,
        altitudeAccuracyMeters: r.altitudeAccuracyMeters,
        latitude: r.latitude,
        longitude: r.longitude,
        positionAccuracyMeters: r.positionAccuracyMeters,
        timestamp: r.timestamp,
      );

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _gpsAltitudeSubscription?.cancel();
    _barometerAltitudeSubscription?.cancel();
    // NEU (README Abschnitt 39): CompassService hält jetzt mehrere
    // Sensor-Subscriptions (Gyro, Beschleunigung, Magnetometer) und
    // einen Controller und muss deshalb freigegeben werden.
    unawaited(_compassService.dispose());
    unawaited(_altitudeService.dispose());
    unawaited(_barometerAltitudeService.dispose());
    WakelockPlus.disable();
    super.dispose();
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

  /// NEU (README Abschnitt 59): Die für den Standort ermittelte Missweisung
  /// (Deklination), um die der Magnetkurs auf geografisch Nord korrigiert
  /// wird - "O" = Ostmissweisung (magnetisch Nord liegt östlich von
  /// geografisch Nord), "W" = Westmissweisung. Solange sie fehlt (noch kein
  /// Standort), ist der angezeigte Kurs der magnetische.
  String get _declinationText {
    final declination = _compassService.declinationDegrees;
    if (declination == null) return 'Missweisung: unbekannt (magnetischer Kurs)';
    final direction = declination >= 0 ? 'O' : 'W';
    return 'Missweisung: ${_declinationFormat.format(declination.abs())}° $direction';
  }

  /// Textstil der Genauigkeitsangabe unter dem Kurs (einheitlich für alle
  /// Seiten, siehe widgets/accuracy_text_style.dart).
  // TextStyle? _accuracyStyle(BuildContext context) {
  //   final base = Theme.of(context).textTheme.displaySmall;
  //   final baseFontSize = base?.fontSize;
  //   if (base == null || baseFontSize == null) {
  //     return Theme.of(context).textTheme.bodySmall;
  //   }
  //   return base.copyWith(fontSize: baseFontSize * 2 / 3);
  // }
  TextStyle? _accuracyStyle(BuildContext context) => accuracyTextStyle(context);

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

    return _buildBody(context, heading, headingText);
  }

  /// Seitenlayout: Statuszeile oben, darunter die Kompassrose, die den
  /// gesamten übrigen Platz einnimmt (quadratisch, höchstens 600 dp), und
  /// unten die Kursangabe. Die Rose wird per LayoutBuilder aus dem
  /// tatsächlich verfügbaren Platz berechnet; der Textblock bleibt über
  /// FittedBox(scaleDown) auch bei großer Systemschrift in der Breite.
  Widget _buildBody(BuildContext context, double heading, String headingText) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // README Abschnitt 37: Zeigt die auf dieser Seite AKTUELL
            // verwendete Genauigkeitsstufe (fest die von AltitudeService
            // verwendete) sowie einen kurzen optischen Impuls bei jeder
            // neuen Standortmessung. In der Mitte (nur bei Störung) der
            // Chip "Kompass gestört".
            _buildStatusRow(context),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const minDialSize = 120.0;
                  const maxDialSize = 600.0;
                  final dialSize = math
                      .min(constraints.maxWidth, constraints.maxHeight)
                      .clamp(minDialSize, maxDialSize)
                      .toDouble();
                  return Center(
                    child: SizedBox(
                      width: dialSize,
                      height: dialSize,
                      child: CompassDial(headingDegrees: heading),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildTextBlock(context, headingText),
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
              // Störung - öffnet die geführte Kalibrierung. (Die
              // Höhenkalibrierung liegt seit README Abschnitt 61 in der
              // Höhen-Kachel der Start-Seite.)
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

  /// Textblock unterhalb der Kompassrose: nur noch die Kursangabe samt
  /// Genauigkeit (README Abschnitt 58) - alle übrigen Angaben stehen auf der
  /// Start-Seite.
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
        const SizedBox(height: 2),
        AutoHyphenatingText(
          _declinationText,
          style: _accuracyStyle(context),
        ),
      ],
    );
  }
}
