import 'dart:math' as math;

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/start_grid_columns.dart';
import '../models/user_profile.dart';
import '../services/altitude_correction.dart';
import '../services/app_preferences.dart';
import '../services/device_status_service.dart';
import '../services/live_data_service.dart';
import '../services/pressure_trend_service.dart';
import '../services/track_recording_service.dart';
import '../util/coordinate_formatter.dart';
import '../util/speed_formatter.dart';
import 'widgets/compass_dial.dart';
import 'widgets/recording_indicator.dart';

/// Start-/Übersichtsseite (siehe README Abschnitt 56/57): Links eine
/// vertikale Leiste mit den Profilen (Wandern / Segeln / Rad-Moto /
/// Wohnmobil / Eigene), rechts die zum gewählten Profil gehörenden
/// Anzeigen ("Slots") als Kacheln. Das gewählte Profil ist in der Leiste
/// hervorgehoben und wird über [AppPreferences] gespeichert.
///
/// SPALTEN (README Abschnitt 57): Auf schmalen Displays (Smartphone) steht
/// jede Kachel in einer eigenen Zeile - Werte wie Tempo oder Kurs sind
/// dann flache Kacheln (Beschriftung links, Wert rechts), und die
/// Kompassrose bekommt den übrigen Platz. Auf breiten Displays gibt es
/// zwei Spalten mit höheren Kacheln. Einstellbar: Automatisch / 1 / 2
/// Spalten ([StartGridColumns]).
///
/// Die Seite hält ihre Sensoren über [LiveDataService] nur so lange und
/// nur in dem Umfang am Laufen, wie die belegten Slots sie brauchen -
/// beim Verlassen der Seite (Tab-Wechsel) stoppt alles, wie bei den
/// übrigen Seiten (siehe HomeShell).
///
/// Ein Antippen der Tempo- bzw. Kompass-Kachel öffnet die zugehörige
/// Vollansicht (Tacho, Kompass), siehe [onOpenTab]. Die Höhen-Kachel öffnet
/// die Höhenkalibrierung (README Abschnitt 61); Luftdruck und Position haben
/// keine eigene Seite (Abschnitt 58). Die Tempo-Kachel zeigt zusätzlich das
/// Stillstand-/Bewegungs-Symbol (früher in der Statuszeile).
class StartPage extends StatefulWidget {
  final AppPreferences preferences;
  final DeviceStatusService status;
  final PressureTrendService pressureService;

  /// Für den Aufzeichnungs-Indikator unten in der Profil-Leiste (siehe
  /// [RecordingIndicator], README Abschnitt 64).
  final TrackRecordingService recordingService;

  /// Wechselt in HomeShell auf den Tab mit dem übergebenen Index.
  final ValueChanged<int> onOpenTab;

  const StartPage({
    super.key,
    required this.preferences,
    required this.status,
    required this.pressureService,
    required this.recordingService,
    required this.onOpenTab,
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  /// Tab-Indizes in HomeShell (Start 0, Tacho 1, Kompass 2, Track 3,
  /// Einstellungen 4) - bei Änderungen der Tab-Reihenfolge anpassen.
  static const int _tabTacho = 1;
  static const int _tabCompass = 2;
  static const int _tabTrack = 3;

  static final NumberFormat _oneDecimal = NumberFormat('0.0', 'de_DE');
  static final NumberFormat _noDecimal = NumberFormat('0', 'de_DE');

  /// Höhen der flachen Kacheln im einspaltigen Layout.
  static const double _compactTileHeight = 80;
  static const double _compactTallTileHeight = 88;
  static const double _compactMapTileHeight = 96;

  late final LiveDataService _live = LiveDataService(
    status: widget.status,
    pressureService: widget.pressureService,
    accuracyMode: widget.preferences.speedAccuracyMode,
  );

  @override
  void initState() {
    super.initState();
    // Bildschirm bleibt an, solange die Start-Seite sichtbar ist - analog
    // zur Tacho- und Kompass-Seite.
    WakelockPlus.enable();
    widget.preferences.addListener(_syncRequirements);
    _syncRequirements();
  }

  /// Passt die laufenden Sensoren an die aktuelle Slot-Belegung an (bei
  /// Start und bei jedem Profil-/Belegungswechsel).
  void _syncRequirements() {
    final profile = widget.preferences.userProfile;
    _live.setRequirements(
      profile == null ? <SlotType>{} : widget.preferences.slotsFor(profile).toSet(),
    );
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_syncRequirements);
    _live.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.preferences, _live]),
        builder: (context, _) {
          final profile = widget.preferences.userProfile;
          return Row(
            children: [
              _buildProfileRail(context, profile),
              const VerticalDivider(width: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: profile == null ? _buildHint(context) : _buildContent(context, profile),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==== Profil-Leiste ====

  /// Vertikale Leiste links, unten darunter der Aufzeichnungs-Indikator
  /// (roter Punkt bzw. Pause-Symbol, nur bei laufender/pausierter
  /// Aufzeichnung; Antippen öffnet die Track-Seite). Die Umhüllung des
  /// Rails aus SingleChildScrollView/IntrinsicHeight ist das in der
  /// Flutter-Dokumentation beschriebene Muster, damit die Leiste auf sehr
  /// niedrigen Displays scrollt statt überzulaufen.
  Widget _buildProfileRail(BuildContext context, UserProfile? selected) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Expanded(child: _buildProfileRailButtons(context, selected)),
          RecordingIndicator(
            service: widget.recordingService,
            onTap: () => widget.onOpenTab(_tabTrack),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRailButtons(BuildContext context, UserProfile? selected) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: selected?.index,
              onDestinationSelected: (index) => widget.preferences.setUserProfile(UserProfile.values[index]),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final profile in UserProfile.values)
                  NavigationRailDestination(
                    icon: Icon(profile.icon),
                    // Bewusst normales Text-Widget (kurze Einzeiler in
                    // beengtem Layout, siehe README Abschnitt 13).
                    label: Text(
                      profile.shortLabel,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==== Inhalt ====

  Widget _buildHint(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            AutoHyphenatingText(
              'Wie bist du unterwegs?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            AutoHyphenatingText(
              'Wähle links dein Profil - die Anzeigen auf dieser Seite und '
              'die Einheit des Tempos passen sich daran an.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, UserProfile profile) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: AutoHyphenatingText(profile.label, style: theme.textTheme.titleMedium),
        ),
        Expanded(child: _buildGrid(context, profile)),
      ],
    );
  }

  /// Wählt anhand der Einstellung (und bei "Automatisch" anhand der
  /// Breite des Kachelbereichs) das ein- oder zweispaltige Layout.
  Widget _buildGrid(BuildContext context, UserProfile profile) {
    final slots = widget.preferences.slotsFor(profile);
    if (slots.isEmpty) {
      return Center(
        child: AutoHyphenatingText(
          'Für dieses Profil sind keine Anzeigen belegt. Unter Einstellungen '
          '→ Start lassen sich welche hinzufügen.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final oneColumn = switch (widget.preferences.startGridColumns) {
          StartGridColumns.one => true,
          StartGridColumns.two => false,
          StartGridColumns.auto => constraints.maxWidth < StartGridColumns.autoTwoColumnMinWidth,
        };
        return oneColumn ? _buildSingleColumn(context, profile, slots, constraints) : _buildTwoColumns(context, profile, slots, constraints);
      },
    );
  }

  double _compactHeightOf(SlotType slot) {
    switch (slot) {
      case SlotType.position:
        return _compactTallTileHeight;
      case SlotType.mapPreset:
        return _compactMapTileHeight;
      default:
        return _compactTileHeight;
    }
  }

  /// Eine Spalte: flache Kacheln für Textwerte, die Kompassrose erhält den
  /// verbleibenden Platz (mindestens 200, höchstens 380 dp) - ist kein
  /// Kompass belegt, bleiben die Kacheln flach und die Seite scrollt bei
  /// Bedarf.
  Widget _buildSingleColumn(
    BuildContext context,
    UserProfile profile,
    List<SlotType> slots,
    BoxConstraints constraints,
  ) {
    const spacing = 8.0;
    var fixedSum = 0.0;
    for (final slot in slots) {
      if (slot != SlotType.compass) fixedSum += _compactHeightOf(slot);
    }
    final remaining = constraints.maxHeight - fixedSum - spacing * (slots.length - 1);
    final compassHeight = math.min(380.0, math.max(200.0, remaining));

    return SingleChildScrollView(
      child: Column(
        children: [
          for (var i = 0; i < slots.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : spacing),
              child: SizedBox(
                height: slots[i] == SlotType.compass ? compassHeight : _compactHeightOf(slots[i]),
                child: _buildSlot(
                  context,
                  profile,
                  slots[i],
                  compact: slots[i] != SlotType.compass,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Zwei Spalten; die Kachelhöhe richtet sich nach dem verfügbaren Platz
  /// (mindestens 130 dp, sonst scrollt die Seite).
  Widget _buildTwoColumns(
    BuildContext context,
    UserProfile profile,
    List<SlotType> slots,
    BoxConstraints constraints,
  ) {
    const spacing = 8.0;
    const minTileHeight = 130.0;
    final rows = (slots.length / 2).ceil();
    final fitted = (constraints.maxHeight - spacing * (rows - 1)) / rows;
    final tileHeight = math.max(minTileHeight, fitted);

    return SingleChildScrollView(
      child: Column(
        children: [
          for (var row = 0; row < rows; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : spacing),
              child: SizedBox(
                height: tileHeight,
                child: Row(
                  children: [
                    Expanded(child: _buildSlot(context, profile, slots[row * 2], compact: false)),
                    if (row * 2 + 1 < slots.length) ...[
                      const SizedBox(width: spacing),
                      Expanded(
                        child: _buildSlot(context, profile, slots[row * 2 + 1], compact: false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlot(
    BuildContext context,
    UserProfile profile,
    SlotType slot, {
    required bool compact,
  }) {
    switch (slot) {
      case SlotType.speed:
        return _buildSpeedTile(context, compact);
      case SlotType.course:
        return _buildCourseTile(context, compact);
      case SlotType.altitude:
        return _buildAltitudeTile(context, compact);
      case SlotType.pressure:
        return _buildPressureTile(context, compact);
      case SlotType.position:
        return _buildPositionTile(context, compact);
      case SlotType.compass:
        return _buildCompassTile(context);
      case SlotType.mapPreset:
        return _buildMapPresetTile(context, profile, compact);
    }
  }

  // ==== Kachel-Rahmen ====

  /// Rahmen der hohen Kacheln: Kopfzeile (Symbol + Name) und beliebiger
  /// Inhalt.
  Widget _tile(
    BuildContext context, {
    required SlotType slot,
    required Widget child,
    VoidCallback? onTap,
    Widget? headerTrailing,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(slot.icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      slot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  if (headerTrailing != null) ...[
                    const SizedBox(width: 6),
                    headerTrailing,
                  ],
                ],
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  /// Rahmen der flachen Kacheln (einspaltiges Layout): Symbol und
  /// Beschriftung (mit optionaler Zeile darunter) links, [trailing]
  /// (Wert) rechtsbündig.
  Widget _compactTile(
    BuildContext context, {
    required SlotType slot,
    required Widget trailing,
    String? subtitle,
    bool subtitleIsError = false,
    int subtitleMaxLines = 2,
    int leftFlex = 5,
    int rightFlex = 5,
    VoidCallback? onTap,
    Widget? headerTrailing,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(slot.icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                flex: leftFlex,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            slot.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        if (headerTrailing != null) ...[
                          const SizedBox(width: 6),
                          headerTrailing,
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: subtitleIsError ? theme.colorScheme.error : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: rightFlex,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Großer Wert (optional mit kleinerer Einheit) - flach etwas kleiner.
  Widget _valueText(BuildContext context, String value, String? unit, {required bool compact}) {
    final theme = Theme.of(context);
    final base = compact ? theme.textTheme.headlineMedium : theme.textTheme.displaySmall;
    return Text.rich(
      TextSpan(
        text: value,
        style: base?.copyWith(fontWeight: FontWeight.bold),
        children: [
          if (unit != null) TextSpan(text: ' $unit', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  /// Kachel mit einem großen Wert und einer Zeile dazu. Flach (einspaltig):
  /// Beschriftung samt Zeile links, Wert rechts. Hoch (zweispaltig): Wert
  /// mittig, Zeile darunter. [subtitleIsError] färbt die Zeile in der
  /// Fehlerfarbe.
  Widget _valueTile(
    BuildContext context, {
    required SlotType slot,
    required String value,
    required bool compact,
    String? unit,
    String? subtitle,
    bool subtitleIsError = false,
    VoidCallback? onTap,
    Widget? headerTrailing,
  }) {
    if (compact) {
      return _compactTile(
        context,
        slot: slot,
        subtitle: subtitle,
        subtitleIsError: subtitleIsError,
        onTap: onTap,
        headerTrailing: headerTrailing,
        trailing: _valueText(context, value, unit, compact: true),
      );
    }
    final theme = Theme.of(context);
    return _tile(
      context,
      slot: slot,
      onTap: onTap,
      headerTrailing: headerTrailing,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _valueText(context, value, unit, compact: false),
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: subtitleIsError ? theme.colorScheme.error : null,
              ),
            ),
        ],
      ),
    );
  }

  /// Hinweis, falls GPS-Daten wegen Standortdienst/Berechtigung fehlen -
  /// null, solange alles in Ordnung ist.
  String? get _locationProblem {
    switch (_live.locationState) {
      case LiveLocationState.checking:
      case LiveLocationState.ready:
        return null;
      case LiveLocationState.serviceDisabled:
        return 'Standortdienst aus';
      case LiveLocationState.denied:
        return 'Standort-Berechtigung fehlt';
      case LiveLocationState.deniedForever:
        return 'Berechtigung in den App-Einstellungen erteilen';
    }
  }

  // ==== Kacheln ====

  static String _signed(double v) => '${v >= 0 ? '+' : ''}${_oneDecimal.format(v)}';

  /// Dialog zur manuellen Höhenkalibrierung (README Abschnitt 54, seit
  /// Abschnitt 61 hier statt auf der Kompass-Seite): Der Nutzer gibt eine
  /// bekannte Höhe (m ü. NN) ein, der Versatz zur aktuell angezeigten Höhe
  /// wird gespeichert. Bewusst normale Text-Widgets im AlertDialog (siehe
  /// README Abschnitt 13).
  Future<void> _openAltitudeCalibration() async {
    final shown = _live.altitudeMeters;
    final messenger = ScaffoldMessenger.of(context);
    if (shown == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _live.altitudePending ? 'Die Höhe wird noch ermittelt - bitte kurz warten.' : 'Noch keine Höhe verfügbar.',
          ),
        ),
      );
      return;
    }
    final correction = AltitudeCorrection.instance;
    final currentOffset = widget.preferences.altitudeManualOffsetMeters;
    final controller = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Höhe kalibrieren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gib die tatsächliche Höhe deines Standorts ein (m ü. NN, z. B. von '
              'einem Höhenpunkt oder einer Karte). Am besten nach einigen Minuten '
              'im Freien.',
            ),
            const SizedBox(height: 12),
            Text('Angezeigt: ${_oneDecimal.format(shown)} m'),
            Text(
              correction.hasMslCorrection
                  ? 'NN-Korrektur (Android): ${_signed(correction.mslCorrectionMeters)} m'
                  : (correction.mslSupported ? 'NN-Korrektur (Android): noch nicht ermittelt' : 'NN-Korrektur (Android): erst ab Android 14'),
            ),
            Text('Manueller Versatz: ${_signed(currentOffset)} m'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Tatsächliche Höhe',
                suffixText: 'm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Abbrechen'),
          ),
          if (currentOffset != 0)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('reset'),
              child: const Text('Zurücksetzen'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('apply'),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );

    final text = controller.text;
    controller.dispose();
    if (!mounted || action == null || action == 'cancel') return;

    if (action == 'reset') {
      await widget.preferences.setAltitudeManualOffsetMeters(0);
      return;
    }
    final known = double.tryParse(text.trim().replaceAll(',', '.'));
    if (known == null || known < -500 || known > 9000) {
      messenger.showSnackBar(const SnackBar(content: Text('Ungültige Höhe.')));
      return;
    }
    // Angezeigt = Rohwert + currentOffset, gewünscht = known.
    await widget.preferences.setAltitudeManualOffsetMeters(known - shown + currentOffset);
  }

  Widget _buildSpeedTile(BuildContext context, bool compact) {
    final unit = widget.preferences.speedUnit;
    final ms = _live.speedMs;
    final problem = _locationProblem;
    final accuracyMs = _live.speedAccuracyMs;
    return _valueTile(
      context,
      slot: SlotType.speed,
      compact: compact,
      value: ms == null
          ? '-'
          : SpeedFormatter.format(
              speedMetersPerSecond: ms,
              displayValue: unit.fromMetersPerSecond(ms),
            ),
      unit: unit.symbol,
      subtitle: problem ??
          SpeedFormatter.formatAccuracy(
            accuracyMs == null ? null : unit.fromMetersPerSecond(accuracyMs),
            unit,
          ),
      subtitleIsError: problem != null,
      onTap: () => widget.onOpenTab(_tabTacho),
      headerTrailing: _buildStationaryIcon(),
    );
  }

  /// Stillstand-/Bewegungs-Symbol (früher in der Statuszeile): orange
  /// Pause = Stillstand erkannt, grünes Abspielen = in Bewegung, graues
  /// Symbol = unbekannt.
  Widget _buildStationaryIcon() {
    final stationary = _live.stationary;
    final IconData icon;
    final Color color;
    final String tooltip;
    if (stationary == null) {
      icon = Icons.remove_circle_outline;
      color = Colors.grey;
      tooltip = 'Bewegungszustand unbekannt';
    } else if (stationary) {
      icon = Icons.pause_circle;
      color = Colors.orange;
      tooltip = 'Stillstand erkannt';
    } else {
      icon = Icons.play_circle;
      color = Colors.green;
      tooltip = 'In Bewegung';
    }
    return Tooltip(message: tooltip, child: Icon(icon, size: 22, color: color));
  }

  Widget _buildCourseTile(BuildContext context, bool compact) {
    final course = _live.courseDegrees;
    final problem = _locationProblem;
    return _valueTile(
      context,
      slot: SlotType.course,
      compact: compact,
      value: course == null ? '-' : '${_noDecimal.format(course)}°',
      subtitle: problem ?? (course == null ? 'GPS-Kurs erst ab ca. 4 km/h' : null),
      subtitleIsError: problem != null,
    );
  }

  Widget _buildAltitudeTile(BuildContext context, bool compact) {
    final altitude = _live.altitudeMeters;
    final problem = _locationProblem;
    final String value;
    final String? subtitle;
    if (altitude != null) {
      value = (_live.altitudeFromBarometer ? _oneDecimal : _noDecimal).format(altitude);
      subtitle = 'ü. NN';
    } else if (_live.altitudePending) {
      value = '…';
      subtitle = 'wird ermittelt';
    } else {
      value = '-';
      subtitle = 'nicht verfügbar';
    }
    return _valueTile(
      context,
      slot: SlotType.altitude,
      compact: compact,
      value: value,
      unit: altitude != null ? 'm' : null,
      subtitle: problem ?? subtitle,
      subtitleIsError: problem != null,
      onTap: _openAltitudeCalibration,
      headerTrailing: Tooltip(
        message: 'Antippen zum Kalibrieren',
        child: Icon(Icons.tune, size: 18, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildPressureTile(BuildContext context, bool compact) {
    final reading = _live.pressure;
    if (reading == null) {
      return _valueTile(
        context,
        slot: SlotType.pressure,
        compact: compact,
        value: '-',
        subtitle: 'nicht verfügbar',
      );
    }
    final category = reading.category;
    return _valueTile(
      context,
      slot: SlotType.pressure,
      compact: compact,
      value: _oneDecimal.format(reading.hPa),
      unit: 'hPa',
      subtitle: category == null ? 'Trend: sammle Daten …' : '${category.arrow} ${category.label}',
    );
  }

  Widget _buildPositionTile(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final lat = _live.latitude;
    final lon = _live.longitude;
    final problem = _locationProblem;

    if (lat == null || lon == null) {
      return _valueTile(
        context,
        slot: SlotType.position,
        compact: compact,
        value: '-',
        subtitle: problem ?? 'nicht verfügbar',
        subtitleIsError: problem != null,
      );
    }

    // "Breite: " / "Länge: " / "Position: " weglassen - die Kachel ist
    // schmal, die Zeilen sind auch so eindeutig (N/S bzw. O/W, UTM-Zone).
    final lines = [
      for (final line in CoordinateFormatter.formatPosition(
        lat,
        lon,
        widget.preferences.positionDisplayFormat,
      ))
        line.contains(': ') ? line.substring(line.indexOf(': ') + 2) : line,
    ];
    final accuracy = _live.positionAccuracyMeters;
    final accuracyText = accuracy == null ? 'Genauigkeit unbekannt' : 'Genauigkeit ± ${_noDecimal.format(accuracy)} m';
    final lineStyle = (compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.bold);
    final linesColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact ? CrossAxisAlignment.end : CrossAxisAlignment.center,
      children: [for (final line in lines) Text(line, style: lineStyle)],
    );

    if (compact) {
      return _compactTile(
        context,
        slot: SlotType.position,
        subtitle: accuracyText,
        trailing: linesColumn,
      );
    }

    return _tile(
      context,
      slot: SlotType.position,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: linesColumn),
            ),
          ),
          Text(accuracyText, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Die Kompass-Kachel ist in beiden Layouts hoch: Im einspaltigen
  /// Layout bekommt sie den übrigen Platz der Seite (siehe
  /// [_buildSingleColumn]), die Rose erscheint dadurch größer.
  Widget _buildCompassTile(BuildContext context) {
    final theme = Theme.of(context);
    if (!_live.compassSupported) {
      return _tile(
        context,
        slot: SlotType.compass,
        child: Center(
          child: Text(
            'Kein Kompass-Sensor',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return _tile(
      context,
      slot: SlotType.compass,
      onTap: () => widget.onOpenTab(_tabCompass),
      child: Column(
        children: [
          // Nur die Rose (nicht die ganze Seite) reagiert auf die bis zu
          // 20 Peilungs-Updates pro Sekunde.
          Expanded(
            child: Center(
              child: ValueListenableBuilder<double?>(
                valueListenable: _live.compassHeading,
                builder: (context, heading, _) => CompassDial(headingDegrees: heading ?? 0),
              ),
            ),
          ),
          ValueListenableBuilder<double?>(
            valueListenable: _live.compassHeading,
            builder: (context, heading, _) => Text(
              _live.compassDisturbed ? 'Kompass gestört' : (heading == null ? '-' : '${_noDecimal.format(heading)}°'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _live.compassDisturbed ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPresetTile(BuildContext context, UserProfile profile, bool compact) {
    final theme = Theme.of(context);
    final hasPreset = profile.mapStyle != null;
    final active = widget.preferences.isMapPresetActive(profile);

    Widget action = const SizedBox.shrink();
    if (hasPreset) {
      action = active
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Aktiv', style: theme.textTheme.labelLarge),
              ],
            )
          : FilledButton.tonal(
              onPressed: () async {
                await widget.preferences.applyMapPreset(profile);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Karte für die Track-Seite gesetzt.')),
                );
              },
              child: const Text('Übernehmen'),
            );
    }

    if (compact) {
      return _compactTile(
        context,
        slot: SlotType.mapPreset,
        subtitle: profile.mapPresetDescription,
        subtitleMaxLines: 3,
        leftFlex: 6,
        rightFlex: 4,
        trailing: action,
      );
    }

    return _tile(
      context,
      slot: SlotType.mapPreset,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                profile.mapPresetDescription,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          action,
        ],
      ),
    );
  }
}
