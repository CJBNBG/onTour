import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/speed_display_style.dart';
import '../models/speed_reading.dart';
import '../models/speed_scale.dart';
import '../models/speed_unit.dart';
import '../services/app_preferences.dart';
import '../services/device_status_service.dart';
import '../services/speed_service.dart';
import '../util/speed_formatter.dart';
import 'widgets/accuracy_badge.dart';
import 'widgets/accuracy_text_style.dart';
import 'widgets/analog_speed_gauge.dart';
import 'widgets/measurement_pulse_indicator.dart';
import 'widgets/seven_segment_display.dart';
import 'widgets/stacked_segment_label.dart';

/// Zeigt die aktuelle Geschwindigkeit möglichst bildschirmfüllend an,
/// darunter (klein) die Genauigkeit sowie - sofern verfügbar - die Anzahl
/// der einbezogenen Satelliten. Über einen Schieberegler kann zwischen
/// m/s, km/h und Knoten wechseln werden.
class SpeedPage extends StatefulWidget {
  final AppPreferences preferences;

  /// NEU: gemeinsamer Gerätestatus aus HomeShell (Satelliten/Stillstand,
  /// angezeigt im Statusbereich unter der App-Leiste).
  final DeviceStatusService status;

  const SpeedPage({super.key, required this.preferences, required this.status});

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  final SpeedService _speedService = SpeedService();

  StreamSubscription<SpeedReading>? _speedSubscription;

  LocationAvailability _availability = LocationAvailability.checking;
  SpeedReading? _latestReading;

  /// NEU (siehe README Abschnitt 37): Wird bei jeder neuen
  /// Geschwindigkeitsmessung erhöht - dient MeasurementPulseIndicator als
  /// Auslöser für den kurzen optischen Impuls, kennt selbst keine
  /// fachliche Bedeutung.
  int _measurementTick = 0;

  /// Zuletzt vom Bewegungssensor gemeldeter Stillstands-Status. null,
  /// solange noch keine Messung vorliegt bzw. kein Sensor verfügbar ist -
  /// in diesem Fall wird ausschließlich der GPS-Rohwert verwendet.
  bool? get _isStationary => widget.status.sensorStationary;

  /// Zuletzt verarbeiteter Sensorzustand - verhindert, dass die eigenen
  /// Rückmeldungen an den Statusbereich (siehe _reportStationary) hier
  /// erneut eine Verarbeitung auslösen.
  bool? _lastSensorStationary;

  void _onStatusChanged() {
    final sensor = widget.status.sensorStationary;
    if (sensor == _lastSensorStationary) return;
    _lastSensorStationary = sensor;
    if (!mounted) return;
    setState(() {});
    _reportStationary();
  }

  /// Kombinierter Stillstand der Tacho-Seite (Sensor UND GPS-Rohwert unter
  /// der Schwelle) - null ohne GPS-Messung.
  bool _isStationaryOverride(SpeedReading reading) {
    final rawKmh = SpeedUnit.kilometersPerHour.fromMetersPerSecond(reading.speedMetersPerSecond);
    return _isStationary == true && rawKmh < _stationaryOverrideThresholdKmh;
  }

  void _reportStationary() {
    final reading = _latestReading;
    widget.status.reportSpeedPageStationary(
      reading == null ? null : _isStationaryOverride(reading),
    );
  }

  /// Unterhalb dieser GPS-Rohgeschwindigkeit (km/h) wird ein vom
  /// Bewegungssensor bestätigter Stillstand als "echte Null" gewertet
  /// (siehe MotionService-Klassenkommentar für die Begründung dieser
  /// Kombination aus zwei unabhängigen Signalen).
  static const _stationaryOverrideThresholdKmh = 8.0;

  @override
  void initState() {
    super.initState();
    // Bildschirm bleibt an, solange die Tacho-Seite sichtbar ist (typischer
    // Anwendungsfall: Gerät liegt während der Fahrt sichtbar, Anzeige soll
    // nicht durch den automatischen Bildschirm-Sperrbildschirm verdeckt
    // werden). Wird beim Verlassen der Seite in dispose() wieder aufgehoben.
    WakelockPlus.enable();
    _lastSensorStationary = widget.status.sensorStationary;
    widget.status.addListener(_onStatusChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    final availability = await _speedService.checkAvailability();
    if (!mounted) return;
    setState(() => _availability = availability);

    if (availability != LocationAvailability.ready) return;

    _speedSubscription = _speedService
        .speedStream(widget.preferences.speedAccuracyMode)
        .listen(
      (reading) {
        if (!mounted) return;
        setState(() {
          _latestReading = reading;
          _measurementTick++;
        });
        _reportStationary();
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _availability = LocationAvailability.serviceDisabled);
      },
    );
  }

  @override
  void dispose() {
    _speedSubscription?.cancel();
    widget.status.removeListener(_onStatusChanged);
    // Verzögert, da dispose() mitten im Neuaufbau des Widget-Baums läuft -
    // ein sofortiges Benachrichtigen der Statusleiste wäre dort unzulässig.
    final status = widget.status;
    scheduleMicrotask(() => status.reportSpeedPageStationary(null));
    // Stoppt zuverlässig den GPS-Empfang, sobald die Seite verlassen wird
    // (siehe HomeShell - Seiten werden bewusst nicht per IndexedStack im
    // Hintergrund weiterlaufen gelassen, sondern bei Tab-Wechsel disposed).
    unawaited(_speedService.dispose());
    // Bildschirm darf wieder automatisch sperren, sobald die Tacho-Seite
    // verlassen wird.
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Horizontales Padding bewusst identisch zu SettingsPage (dort
        // ListView(padding: EdgeInsets.all(16))) gewählt - nur so werden
        // die beiden SegmentedButtons (hier und in den Einstellungen)
        // exakt gleich breit (siehe auch SizedBox(width: double.infinity)
        // weiter unten in _buildUnitSelector).
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            // NEU (siehe README Abschnitt 37): Zeigt die auf dieser Seite
            // AKTUELL verwendete Genauigkeitsstufe (hier: die vom Nutzer
            // in den Einstellungen gewählte, siehe Abschnitt 4) sowie
            // einen kurzen optischen Impuls bei jeder neuen Messung.
            _buildStatusRow(context),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AccuracyBadge(mode: widget.preferences.speedAccuracyMode),
        MeasurementPulseIndicator(pulseKey: _measurementTick),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_availability) {
      case LocationAvailability.checking:
        return const Center(child: CircularProgressIndicator());
      case LocationAvailability.serviceDisabled:
        return _buildHint(
          icon: Icons.location_off,
          text: 'Der Standortdienst des Geräts ist deaktiviert.',
          buttonLabel: 'Standorteinstellungen öffnen',
          onPressed: () => _speedService.checkAvailability().then(_applyAvailability),
        );
      case LocationAvailability.permissionDenied:
        return _buildHint(
          icon: Icons.location_disabled,
          text: 'Für die Geschwindigkeitsanzeige wird die Standort-Berechtigung benötigt.',
          buttonLabel: 'Erneut versuchen',
          onPressed: _initialize,
        );
      case LocationAvailability.permissionDeniedForever:
        return _buildHint(
          icon: Icons.settings,
          text: 'Die Standort-Berechtigung wurde dauerhaft abgelehnt. '
              'Bitte in den App-Einstellungen des Geräts erteilen.',
          buttonLabel: 'App-Einstellungen öffnen',
          onPressed: () => _speedService.checkAvailability().then(_applyAvailability),
        );
      case LocationAvailability.ready:
        return _buildSpeedDisplay(context);
    }
  }

  void _applyAvailability(LocationAvailability availability) {
    if (!mounted) return;
    setState(() => _availability = availability);
    if (availability == LocationAvailability.ready) _initialize();
  }

  Widget _buildHint({
    required IconData icon,
    required String text,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          AutoHyphenatingText(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onPressed, child: AutoHyphenatingText(buttonLabel)),
        ],
      ),
    );
  }

  Widget _buildSpeedDisplay(BuildContext context) {
    final unit = widget.preferences.speedUnit;
    final reading = _latestReading;

    // Kombination aus GPS-Rohwert und Bewegungssensor (siehe
    // MotionService-Klassenkommentar): Nur wenn der GPS-Rohwert bereits
    // klein ist UND der Bewegungssensor Stillstand bestätigt, wird auf
    // eine "echte Null" korrigiert - das unterdrückt das für ruhende
    // Geräte typische GPS-Rauschen, ohne eine tatsächliche (schnelle)
    // Fahrt jemals fälschlich auf 0 zu setzen.
    final stationaryOverrideActive = reading != null && _isStationaryOverride(reading);
    final effectiveSpeedMs =
        stationaryOverrideActive ? 0.0 : reading?.speedMetersPerSecond;

    final displayValue =
        effectiveSpeedMs != null ? unit.fromMetersPerSecond(effectiveSpeedMs) : 0.0;
    final speedText = effectiveSpeedMs != null
        ? SpeedFormatter.format(
            speedMetersPerSecond: effectiveSpeedMs,
            displayValue: displayValue,
          )
        : '-';

    // Zerlegt die formatierte Zahl (z. B. "12,3") in den Vorkommateil
    // ("12", normale Größe) und die EINE Nachkommastelle ("3") - Letztere
    // wird in _buildSpeedNumber hochgestellt und in ca. einem Drittel der
    // Größe direkt hinter der Zahl dargestellt. Ohne aktuelle Messung
    // (speedText == "-") gibt es kein Komma, decimalDigit bleibt dann null.
    var integerPart = speedText;
    String? decimalDigit;
    final commaIndex = speedText.indexOf(',');
    if (commaIndex != -1) {
      integerPart = speedText.substring(0, commaIndex);
      decimalDigit = speedText.substring(commaIndex + 1);
    }

    final accuracyDisplayValue = reading?.speedAccuracyMetersPerSecond != null
        ? unit.fromMetersPerSecond(reading!.speedAccuracyMetersPerSecond!)
        : null;

    final analog = widget.preferences.speedDisplayStyle == SpeedDisplayStyle.analog;

    final column = Column(
      children: [
        // Die Geschwindigkeit nimmt bewusst den mit Abstand größten Teil
        // des verfügbaren Platzes ein. Die Einheit steht bewusst UNTER
        // (statt neben) der Zahl, damit die Sieben-Segment-Anzeige die
        // volle verfügbare Breite für sich beanspruchen kann - Expanded +
        // FittedBox skaliert sie automatisch auf die maximal mögliche
        // Größe.
        Expanded(
          child: Center(
            child: analog
                // NEU: Analoges Rundinstrument (Einheit steht im Zifferblatt).
                ? AnalogSpeedGauge(
                    value: displayValue,
                    maxValue: widget.preferences.speedScaleMax(unit),
                    valueText: speedText,
                    unitSymbol: unit.symbol,
                  )
                : FittedBox(
                    fit: BoxFit.contain,
                    child: _buildSpeedNumber(integerPart, decimalDigit),
                  ),
          ),
        ),
        if (!analog)
          AutoHyphenatingText(
            unit.symbol,
            style: TextStyle(
              fontSize: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        // Seitlicher Abstand hält die Genauigkeitszeile frei vom Knopf
        // unten rechts (siehe unten); FittedBox verkleinert sie nur, falls
        // der Platz dafür nicht reicht - wie auf der Kompass-Seite.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AutoHyphenatingText(
              SpeedFormatter.formatAccuracy(accuracyDisplayValue, unit),
              style: _readableInfoStyle(context),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );

    // NEU: Anzeigeeinheit und Skalenende liegen nicht mehr als breite
    // Auswahl unter dem Instrument, sondern hinter einem kleinen Knopf
    // unten rechts - das Instrument bekommt dadurch mehr Platz.
    return Stack(
      fit: StackFit.expand,
      children: [
        column,
        Positioned(
          right: 0,
          bottom: 0,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Einheit und Skala',
            // App-Farbe (Teal, aus dem colorSchemeSeed des Themes) statt der
            // Standardfarbe primaryContainer.
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onPressed: _showUnitSheet,
            child: const Icon(Icons.tune),
          ),
        ),
      ],
    );
  }

  /// Öffnet die Vorwahl für Anzeigeeinheit und - nur bei analoger
  /// Darstellung - das Skalenende der gerade gewählten Einheit. Die
  /// Änderungen wirken sofort im Hintergrund; ListenableBuilder baut das
  /// Fenster bei einem Einheitenwechsel mit den passenden Skalenstufen neu
  /// auf.
  void _showUnitSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: widget.preferences,
          builder: (context, _) {
            final unit = widget.preferences.speedUnit;
            final analog = widget.preferences.speedDisplayStyle == SpeedDisplayStyle.analog;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildUnitSelector(context, unit),
                  if (analog) ...[
                    const SizedBox(height: 20),
                    _buildScaleSelector(context, unit),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Auswahl des Skalenendes für den analogen Tacho - die Segmente richten
  /// sich nach der gewählten Einheit (siehe SpeedScale), jede Einheit
  /// behält ihre eigene letzte Wahl (AppPreferences.speedScaleMax).
  /// Normales Text statt AutoHyphenatingText (siehe README Abschnitt 13).
  Widget _buildScaleSelector(BuildContext context, SpeedUnit unit) {
    return Column(
      children: [
        AutoHyphenatingText(
          'Skalenende (${unit.symbol})',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: [
              for (final value in SpeedScale.optionsFor(unit))
                ButtonSegment(value: value, label: Text('$value')),
            ],
            selected: {widget.preferences.speedScaleMax(unit)},
            onSelectionChanged: (selection) {
              widget.preferences.setSpeedScaleMax(unit, selection.first);
            },
          ),
        ),
      ],
    );
  }

  /// Textstil der Genauigkeitszeile - einheitlich für alle Seiten (siehe
  /// widgets/accuracy_text_style.dart).
  TextStyle? _readableInfoStyle(BuildContext context) => accuracyTextStyle(context);

  /// Baut die Geschwindigkeitsanzeige aus dem Vorkommateil (normale
  /// Sieben-Segment-Größe) und - sofern vorhanden - der einen
  /// Nachkommastelle, die deutlich kleiner (ca. ein Drittel der Höhe) und
  /// per Row-Ausrichtung am oberen Rand ("hochgestellt", wie ein
  /// Exponent) direkt dahinter angezeigt wird, statt wie zuvor als
  /// gleich große Ziffer nach einem Komma.
  Widget _buildSpeedNumber(String integerPart, String? decimalDigit) {
    const mainHeight = 160.0; // Standardhöhe von SevenSegmentDisplay
    const decimalHeight = mainHeight / 3;

    if (decimalDigit == null) {
      return SevenSegmentDisplay(text: integerPart, height: mainHeight);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SevenSegmentDisplay(text: integerPart, height: mainHeight),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SevenSegmentDisplay(text: decimalDigit, height: decimalHeight),
        ),
      ],
    );
  }

  Widget _buildUnitSelector(BuildContext context, SpeedUnit selected) {
    return Column(
      children: [
        AutoHyphenatingText('Anzeigeeinheit', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        // Auf volle Breite gestreckt (SizedBox mit double.infinity) -
        // dadurch exakt so breit wie das SegmentedButton in den
        // Einstellungen (gleiches horizontales Padding, siehe build()) UND
        // jedes Segment bekommt maximal möglichen Platz, damit die
        // Beschriftung (m/s, km/h, kn) sicher einzeilig bleibt.
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<SpeedUnit>(
            segments: [
              ButtonSegment(
                value: SpeedUnit.metersPerSecond,
                // Normales Text statt AutoHyphenatingText (siehe
                // StackedSegmentLabel/README Abschnitt 13); das Symbol
                // steht OBERHALB des Textes, damit dieser auch auf
                // schmalen Displays einzeilig bleibt.
                label: StackedSegmentLabel(
                  icon: Icons.person,
                  text: SpeedUnit.metersPerSecond.symbol,
                ),
              ),
              ButtonSegment(
                value: SpeedUnit.kilometersPerHour,
                label: StackedSegmentLabel(
                  icon: Icons.directions_car,
                  text: SpeedUnit.kilometersPerHour.symbol,
                ),
              ),
              ButtonSegment(
                value: SpeedUnit.milesPerHour,
                label: StackedSegmentLabel(
                  icon: Icons.speed,
                  text: SpeedUnit.milesPerHour.symbol,
                ),
              ),
              ButtonSegment(
                value: SpeedUnit.knots,
                label: StackedSegmentLabel(
                  icon: Icons.sailing,
                  text: SpeedUnit.knots.symbol,
                ),
              ),
            ],
            showSelectedIcon: false,
            selected: {selected},
            onSelectionChanged: (selection) {
              widget.preferences.setSpeedUnit(selection.first);
            },
          ),
        ),
      ],
    );
  }
}
