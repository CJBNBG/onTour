import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/speed_reading.dart';
import '../models/speed_unit.dart';
import '../services/app_preferences.dart';
import '../services/motion_service.dart';
import '../services/satellite_service.dart';
import '../services/speed_service.dart';
import '../util/speed_formatter.dart';
import 'widgets/seven_segment_display.dart';

/// Zeigt die aktuelle Geschwindigkeit möglichst bildschirmfüllend an,
/// darunter (klein) die Genauigkeit sowie - sofern verfügbar - die Anzahl
/// der einbezogenen Satelliten. Über einen Schieberegler kann zwischen
/// m/s, km/h und Knoten wechseln werden.
class SpeedPage extends StatefulWidget {
  final AppPreferences preferences;

  const SpeedPage({super.key, required this.preferences});

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  final SpeedService _speedService = SpeedService();
  final SatelliteService _satelliteService = SatelliteService();
  final MotionService _motionService = MotionService();

  StreamSubscription<SpeedReading>? _speedSubscription;
  StreamSubscription<int>? _satelliteSubscription;
  StreamSubscription<bool>? _motionSubscription;

  LocationAvailability _availability = LocationAvailability.checking;
  SpeedReading? _latestReading;
  int? _satelliteCount;

  /// Zuletzt vom Bewegungssensor gemeldeter Stillstands-Status. null,
  /// solange noch keine Messung vorliegt bzw. kein Sensor verfügbar ist -
  /// in diesem Fall wird ausschließlich der GPS-Rohwert verwendet.
  bool? _isStationary;

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
    _motionSubscription = _motionService.isStationaryStream().listen((stationary) {
      if (!mounted) return;
      setState(() => _isStationary = stationary);
    });
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
        setState(() => _latestReading = reading);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _availability = LocationAvailability.serviceDisabled);
      },
    );

    _satelliteSubscription = _satelliteService.satelliteCountStream().listen(
      (count) {
        if (!mounted) return;
        setState(() => _satelliteCount = count);
      },
    );
  }

  @override
  void dispose() {
    _speedSubscription?.cancel();
    _satelliteSubscription?.cancel();
    _motionSubscription?.cancel();
    // Stoppt zuverlässig den GPS-Empfang, sobald die Seite verlassen wird
    // (siehe HomeShell - Seiten werden bewusst nicht per IndexedStack im
    // Hintergrund weiterlaufen gelassen, sondern bei Tab-Wechsel disposed).
    unawaited(_speedService.dispose());
    unawaited(_motionService.dispose());
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
        child: _buildBody(context),
      ),
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
    final rawSpeedKmh =
        reading != null ? SpeedUnit.kilometersPerHour.fromMetersPerSecond(reading.speedMetersPerSecond) : 0.0;
    final stationaryOverrideActive = reading != null &&
        _isStationary == true &&
        rawSpeedKmh < _stationaryOverrideThresholdKmh;
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

    return Column(
      children: [
        // Die Geschwindigkeit nimmt bewusst den mit Abstand größten Teil
        // des verfügbaren Platzes ein. Die Einheit steht bewusst UNTER
        // (statt neben) der Zahl, damit die Sieben-Segment-Anzeige die
        // volle verfügbare Breite für sich beanspruchen kann - Expanded +
        // FittedBox skaliert sie automatisch auf die maximal mögliche
        // Größe.
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: _buildSpeedNumber(integerPart, decimalDigit),
            ),
          ),
        ),
        AutoHyphenatingText(
          unit.symbol,
          style: TextStyle(
            fontSize: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        AutoHyphenatingText(
          SpeedFormatter.formatAccuracy(accuracyDisplayValue, unit),
          style: _readableInfoStyle(context),
        ),
        const SizedBox(height: 4),
        AutoHyphenatingText(
          _satelliteCount != null
              ? 'Satelliten (Fix): $_satelliteCount'
              : 'Satelliten: nicht verfügbar',
          style: _readableInfoStyle(context),
        ),
        const SizedBox(height: 4),
        // Diese Zeile ist bewusst IMMER sichtbar (nicht nur bei aktiver
        // Korrektur) und zeigt sonst "-" an, statt komplett zu
        // verschwinden - ein ständig erscheinendes/verschwindendes
        // Element an dieser Stelle wirkte zusätzlich zum eigentlichen
        // Flackern der Geschwindigkeitsanzeige selbst wie ein zweites,
        // unabhängiges Flackern des Layouts.
        AutoHyphenatingText(
          stationaryOverrideActive ? 'Stillstand erkannt - Anzeige auf 0 korrigiert' : 'Messung aktiv',
          style: _readableInfoStyle(context)?.copyWith(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 24),
        _buildUnitSelector(context, unit),
      ],
    );
  }

  /// Textstil für die drei Info-Zeilen unterhalb der Einheiten-Angabe
  /// (Genauigkeit, Satellitenanzahl, Stillstands-/Messungs-Status) - auf
  /// Wunsch etwa doppelt so groß wie das normale bodySmall, damit sie
  /// auch während der Fahrt (z. B. im Randbereich des Blickfelds) gut
  /// lesbar sind.
  TextStyle? _readableInfoStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall;
    final baseFontSize = base?.fontSize;
    if (base == null || baseFontSize == null) return base;
    return base.copyWith(fontSize: baseFontSize * 2);
  }

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
                // Bewusst normales Text-Widget statt AutoHyphenatingText:
                // Letzteres nutzt intern einen LayoutBuilder zur
                // Breitenmessung, SegmentedButton muss für gleich breite
                // Segmente aber die intrinsische Breite seiner Labels
                // berechnen - das verträgt sich technisch nicht mit einem
                // LayoutBuilder als Kind ("LayoutBuilder does not support
                // returning intrinsic dimensions"). Bei den hier sehr
                // kurzen Einheiten-Symbolen (m/s, km/h, kn) wird ohnehin
                // nie umgebrochen, Silbentrennung wäre wirkungslos.
                label: Text(SpeedUnit.metersPerSecond.symbol),
                icon: const Icon(Icons.person),
              ),
              ButtonSegment(
                value: SpeedUnit.kilometersPerHour,
                label: Text(SpeedUnit.kilometersPerHour.symbol),
                icon: const Icon(Icons.directions_car),
              ),
              ButtonSegment(
                value: SpeedUnit.knots,
                label: Text(SpeedUnit.knots.symbol),
                icon: const Icon(Icons.sailing),
              ),
            ],
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
