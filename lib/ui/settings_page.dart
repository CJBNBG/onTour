import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../models/map_style.dart';
import '../models/position_display_format.dart';
import '../models/route_overlay.dart';
import '../models/speed_display_style.dart';
import '../models/speed_accuracy_mode.dart';
import '../models/speed_scale.dart';
import '../models/speed_unit.dart';
import '../models/start_grid_columns.dart';
import '../models/user_profile.dart';
import '../services/app_preferences.dart';
import '../util/external_link.dart';
import 'widgets/stacked_segment_label.dart';

/// Einstellungsseite, unterteilt in Unterreiter (siehe README Abschnitt
/// 24, seit Abschnitt 57 vier):
/// - **Start** (erster Reiter, seit Abschnitt 62): Spalten der Start-Seite
///   und Belegung der Anzeigen je Profil (README Abschnitt 57).
/// - **Anzeige**: Anzeigemodus (System/Dark/Light) - die Einstellung, die
///   am ehesten "im Vorbeigehen" angepasst wird.
/// - **Karten**: Basiskarte, Overlays, Quellen (Abschnitt 51/52).
/// - **Erweitert**: seltener benötigte, technischere Einstellungen
///   (Genauigkeits-/Aktualitätsstufe der Geschwindigkeitsmessung sowie die
///   Erinnerung bei anhaltend pausierter Track-Aufzeichnung, siehe
///   Abschnitt 4 bzw. Abschnitt 22) - beide waren zuvor gemeinsam mit dem
///   Anzeigemodus auf einer einzigen, zunehmend überladenen Seite
///   untergebracht.
///
/// Bewusst als StatefulWidget mit eigenem [TabController] statt z. B.
/// eines zusätzlichen Eintrags in der unteren Navigationsleiste von
/// HomeShell umgesetzt - die Unterreiter sind rein visuell/organisatorisch
/// EINE Ebene unterhalb von "Einstellungen", nicht eine fünfte
/// gleichberechtigte Hauptseite.
class SettingsPage extends StatefulWidget {
  final AppPreferences preferences;

  const SettingsPage({super.key, required this.preferences});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

  /// Profil, dessen Anzeigen im Unterreiter "Start" gerade bearbeitet
  /// werden - null = das aktive Profil der Start-Seite.
  UserProfile? _editProfile;

  /// Obergrenze der Pause-Erinnerung in Minuten (0 = aus).
  static const int _maxReminderMinutes = 120;

  late final FixedExtentScrollController _reminderWheelController = FixedExtentScrollController(initialItem: widget.preferences.autoPauseReminderMinutes);

  @override
  void dispose() {
    _tabController.dispose();
    _reminderWheelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            // Bewusst normale Text-Labels statt AutoHyphenatingText - bei
            // den hier kurzen, einzeiligen Bezeichnungen ("Anzeige",
            // "Erweitert") wäre eine Silbentrennung ohnehin nie nötig,
            // analog zur bereits bestehenden Ausnahme bei SegmentedButton
            // (siehe README Abschnitt 13).
            tabs: const [
              Tab(text: 'Start'),
              Tab(text: 'Anzeige'),
              Tab(text: 'Karten'),
              Tab(text: 'Erweitert'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStartTab(context),
                _buildDisplayTab(context),
                _buildMapsTab(context),
                _buildAdvancedTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Unterreiter "Anzeige": aktuell nur der Anzeigemodus - als eigener
  /// Tab dennoch sinnvoll, damit künftige rein optische Einstellungen
  /// (z. B. Akzentfarbe) einen klar zugeordneten Platz haben, statt
  /// zwischen technischeren Einstellungen zu stehen.
  Widget _buildDisplayTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AutoHyphenatingText('Anzeigemodus', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        // Auf volle Breite gestreckt - siehe gleiches Vorgehen und
        // ausführlichere Begründung bei der Einheiten-Auswahl auf der
        // Tacho-Seite (speed_page.dart, _buildUnitSelector).
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            // WICHTIG: Bewusst normales Text-Widget statt
            // AutoHyphenatingText (Ausnahme von der sonst projektweiten
            // Regel, siehe README) - SegmentedButton muss für gleich
            // breite Segmente die intrinsische Breite seiner Labels
            // berechnen, AutoHyphenatingText nutzt dafür intern aber
            // einen LayoutBuilder, der laut Flutter-Dokumentation KEINE
            // intrinsischen Berechnungen unterstützt ("LayoutBuilder
            // does not support returning intrinsic dimensions") - das
            // führt sonst zu einem Laufzeitfehler beim Öffnen der Seite.
            // Bei den kurzen Wörtern System/Hell/Dunkel wäre eine
            // Silbentrennung ohnehin nie nötig.
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: StackedSegmentLabel(icon: Icons.brightness_auto, text: 'System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: StackedSegmentLabel(icon: Icons.light_mode, text: 'Hell'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: StackedSegmentLabel(icon: Icons.dark_mode, text: 'Dunkel'),
              ),
            ],
            showSelectedIcon: false,
            selected: {widget.preferences.themeMode},
            onSelectionChanged: (selection) {
              widget.preferences.setThemeMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 32),
        _buildSpeedDisplayStyleSection(context),
        // NEU: Skalenenden des analogen Tachos - nur sichtbar, solange die
        // analoge Darstellung gewählt ist.
        if (widget.preferences.speedDisplayStyle == SpeedDisplayStyle.analog) ...[
          const SizedBox(height: 32),
          _buildSpeedScaleSection(context),
        ],
        const SizedBox(height: 32),
        _buildPositionDisplayFormatSection(context),
      ],
    );
  }

  // ==== Unterreiter "Start" (README Abschnitt 57) ====

  bool _sameSlots(List<SlotType> a, List<SlotType> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reorderSlots(UserProfile profile, List<SlotType> slots, int oldIndex, int newIndex) {
    // onReorderItem liefert newIndex bereits um den entfernten Eintrag
    // bereinigt - eine eigene Korrektur ist nicht mehr nötig.
    final list = List.of(slots);
    list.insert(newIndex, list.removeAt(oldIndex));
    widget.preferences.setSlotsFor(profile, list);
  }

  Future<void> _addSlot(UserProfile profile) async {
    final current = widget.preferences.slotsFor(profile);
    final available = _availableSlots(profile, current);
    if (available.isEmpty) return;

    final chosen = await showModalBottomSheet<SlotType>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final slot in available)
              ListTile(
                leading: Icon(slot.icon),
                title: Text(slot.label),
                onTap: () => Navigator.of(sheetContext).pop(slot),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    // Neu lesen: Die Belegung kann sich währenddessen geändert haben.
    await widget.preferences.setSlotsFor(
      profile,
      [...widget.preferences.slotsFor(profile), chosen],
    );
  }

  /// Anzeigen, die für [profile] noch hinzugefügt werden können - die
  /// Kartenvorwahl nur bei Profilen, die überhaupt eine Karte vorwählen.
  List<SlotType> _availableSlots(UserProfile profile, List<SlotType> current) {
    return [
      for (final type in SlotType.values)
        if (!current.contains(type) && (type != SlotType.mapPreset || profile.mapStyle != null)) type,
    ];
  }

  /// Unterreiter "Start": Spaltenanzahl der Kacheln sowie Auswahl und
  /// Reihenfolge der Anzeigen je Profil. Die Belegung wird sofort
  /// gespeichert und wirkt sich beim nächsten Öffnen der Start-Seite aus.
  Widget _buildStartTab(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final profile = _editProfile ?? prefs.userProfile ?? UserProfile.hiker;
    final slots = prefs.slotsFor(profile);
    final isDefault = _sameSlots(slots, profile.defaultSlots);
    final canAdd = _availableSlots(profile, slots).isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AutoHyphenatingText('Spalten der Kacheln', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        // Normales Text in den Segmenten, siehe README Abschnitt 13.
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<StartGridColumns>(
            segments: const [
              ButtonSegment(
                value: StartGridColumns.auto,
                label: StackedSegmentLabel(icon: Icons.devices, text: 'Auto'),
              ),
              ButtonSegment(
                value: StartGridColumns.one,
                label: StackedSegmentLabel(icon: Icons.view_agenda, text: '1 Spalte'),
              ),
              ButtonSegment(
                value: StartGridColumns.two,
                label: StackedSegmentLabel(icon: Icons.grid_view, text: '2 Spalten'),
              ),
            ],
            showSelectedIcon: false,
            selected: {prefs.startGridColumns},
            onSelectionChanged: (selection) => prefs.setStartGridColumns(selection.first),
          ),
        ),
        const SizedBox(height: 8),
        AutoHyphenatingText(prefs.startGridColumns.description, style: theme.textTheme.bodySmall),
        const SizedBox(height: 32),
        AutoHyphenatingText('Anzeigen der Start-Seite', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        AutoHyphenatingText(
          'Wähle ein Profil und lege fest, welche Anzeigen in welcher '
          'Reihenfolge erscheinen. Das Griff-Symbol rechts gedrückt halten '
          'und ziehen ändert die Reihenfolge.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in UserProfile.values)
              ChoiceChip(
                avatar: Icon(p.icon, size: 18),
                label: Text(p.shortLabel),
                selected: p == profile,
                onSelected: (_) => setState(() => _editProfile = p),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AutoHyphenatingText(profile.label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) => _reorderSlots(profile, slots, oldIndex, newIndex),
          children: [
            for (var i = 0; i < slots.length; i++)
              ListTile(
                key: ValueKey(slots[i]),
                contentPadding: EdgeInsets.zero,
                leading: Icon(slots[i].icon),
                // Bewusst normales Text-Widget (siehe README Abschnitt 13).
                title: Text(slots[i].label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Entfernen',
                      icon: const Icon(Icons.remove_circle_outline),
                      // Mindestens eine Anzeige bleibt stehen.
                      onPressed: slots.length > 1
                          ? () => prefs.setSlotsFor(profile, [
                                for (final s in slots)
                                  if (s != slots[i]) s,
                              ])
                          : null,
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (canAdd)
              OutlinedButton.icon(
                onPressed: () => _addSlot(profile),
                icon: const Icon(Icons.add),
                label: const Text('Anzeige hinzufügen'),
              ),
            if (!isDefault)
              TextButton(
                onPressed: () => prefs.resetSlotsFor(profile),
                child: const Text('Standard wiederherstellen'),
              ),
          ],
        ),
      ],
    );
  }

  /// NEU: Auswahl der Tacho-Darstellung (digital/analog). Wirkt sofort
  /// (die Tacho-Seite wird bei Änderungen der Einstellungen neu aufgebaut,
  /// kein Sensor-Stream muss neu starten). Normales Text in den Segmenten,
  /// siehe README Abschnitt 13.
  Widget _buildSpeedDisplayStyleSection(BuildContext context) {
    final style = widget.preferences.speedDisplayStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText('Tacho-Darstellung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<SpeedDisplayStyle>(
            segments: const [
              ButtonSegment(
                value: SpeedDisplayStyle.digital,
                label: StackedSegmentLabel(icon: Icons.pin, text: 'Digital'),
              ),
              ButtonSegment(
                value: SpeedDisplayStyle.analog,
                label: StackedSegmentLabel(icon: Icons.speed, text: 'Analog'),
              ),
            ],
            showSelectedIcon: false,
            selected: {style},
            onSelectionChanged: (selection) {
              widget.preferences.setSpeedDisplayStyle(selection.first);
            },
          ),
        ),
        const SizedBox(height: 8),
        AutoHyphenatingText(style.description, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  /// NEU: Skalenende des analogen Tachos, für jede Anzeigeeinheit
  /// separat (vorher auf der Tacho-Seite). Die Wahl gilt immer für die
  /// jeweilige Einheit, unabhängig davon, welche gerade aktiv ist.
  /// Normales Text in den Segmenten, siehe README Abschnitt 13.
  Widget _buildSpeedScaleSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText(
          'Skalenende des analogen Tachos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final unit in SpeedUnit.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(unit.symbol, style: Theme.of(context).textTheme.labelLarge),
          ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: [
                for (final value in SpeedScale.optionsFor(unit)) ButtonSegment(value: value, label: Text('$value')),
              ],
              selected: {widget.preferences.speedScaleMax(unit)},
              onSelectionChanged: (selection) {
                widget.preferences.setSpeedScaleMax(unit, selection.first);
              },
            ),
          ),
        ],
      ],
    );
  }

  /// NEU (siehe README Abschnitt 25): Auswahl des Anzeigeformats für die
  /// aktuelle Position auf der Kompass-Seite (DMS/DMM/DD/UTM). Bewusst im
  /// Unterreiter "Anzeige" (statt "Erweitert") untergebracht - anders als
  /// z. B. die Genauigkeitsstufe der Geschwindigkeitsmessung betrifft
  /// diese Wahl ausschließlich die Darstellung, nicht Akkuverbrauch oder
  /// Sensor-Verhalten, und passt damit inhaltlich besser zum Anzeigemodus
  /// (System/Hell/Dunkel) auf demselben Unterreiter.
  Widget _buildPositionDisplayFormatSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText(
          'Positionsformat (Kompass-Seite)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        RadioGroup<PositionDisplayFormat>(
          groupValue: widget.preferences.positionDisplayFormat,
          onChanged: (selected) {
            if (selected != null) widget.preferences.setPositionDisplayFormat(selected);
          },
          child: Column(
            children: [
              for (final format in PositionDisplayFormat.values)
                RadioListTile<PositionDisplayFormat>(
                  value: format,
                  title: AutoHyphenatingText(format.label),
                  subtitle: AutoHyphenatingText(format.description),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// NEU (siehe README Abschnitt 51): Unterreiter "Karten" - Basiskarte,
  /// Seemarken-Overlay sowie Quellen und Nutzungshinweise aller
  /// Kartenanbieter. Die Auswahl entspricht dem Karten-Button auf der
  /// Track-Seite (derselbe gespeicherte Wert).
  Widget _buildMapsTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AutoHyphenatingText('Basiskarte', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<MapStyle>(
          groupValue: widget.preferences.mapStyle,
          onChanged: (selected) {
            if (selected != null) widget.preferences.setMapStyle(selected);
          },
          child: Column(
            children: [
              for (final style in MapStyle.values)
                RadioListTile<MapStyle>(
                  value: style,
                  title: AutoHyphenatingText(style.label),
                  subtitle: AutoHyphenatingText(style.description),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AutoHyphenatingText('Einblenden', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<RouteOverlay>(
          groupValue: widget.preferences.routeOverlay,
          onChanged: (selected) {
            if (selected != null) widget.preferences.setRouteOverlay(selected);
          },
          child: Column(
            children: [
              for (final overlay in RouteOverlay.values)
                RadioListTile<RouteOverlay>(
                  value: overlay,
                  title: AutoHyphenatingText(overlay.label),
                  subtitle: AutoHyphenatingText(overlay.description),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        AutoHyphenatingText('Quellen und Nutzungshinweise', style: theme.textTheme.titleMedium),
        for (final style in MapStyle.values)
          _buildSourceCard(
            context,
            label: style.label,
            credits: style.creditsLine,
            usage: style.usageNote,
            url: style.infoUrl,
          ),
        for (final overlay in RouteOverlay.values.where((o) => o.isActive))
          _buildSourceCard(
            context,
            label: overlay.label,
            credits: overlay.creditsLine,
            usage: overlay.usageNote,
            url: overlay.infoUrl,
          ),
      ],
    );
  }

  Widget _buildSourceCard(
    BuildContext context, {
    required String label,
    required String credits,
    required String usage,
    required String url,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoHyphenatingText(label, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            AutoHyphenatingText(credits, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            AutoHyphenatingText(usage, style: theme.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openExternalLink(url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Nutzungsbedingungen öffnen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Unterreiter "Erweitert": seltener benötigte, technischere
  /// Einstellungen - aktuell Genauigkeitsstufe der Geschwindigkeitsmessung
  /// (zuvor auf der einzigen Einstellungsseite, siehe Abschnitt 4) sowie
  /// die Erinnerung bei anhaltend pausierter Track-Aufzeichnung (siehe
  /// Abschnitt 22).
  Widget _buildAdvancedTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSpeedAccuracySection(context),
        const SizedBox(height: 32),
        _buildAutoPauseReminderSection(context),
        const SizedBox(height: 32),
        _buildAltitudeCalibrationSection(context),
      ],
    );
  }

  /// NEU (README Abschnitt 54): Zeigt den manuellen Höhenversatz und erlaubt
  /// das Zurücksetzen. Die Kalibrierung selbst erfolgt auf der
  /// Start-Seite (Antippen der Höhen-Kachel, seit Abschnitt 61), weil dort die
  /// aktuell angezeigte Höhe bekannt ist.
  Widget _buildAltitudeCalibrationSection(BuildContext context) {
    final offset = widget.preferences.altitudeManualOffsetMeters;
    final offsetText = offset == 0 ? 'kein Versatz' : '${offset >= 0 ? '+' : ''}${offset.toStringAsFixed(1).replaceAll('.', ',')} m';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText('Höhenkalibrierung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AutoHyphenatingText(
          'Die Höhe wird automatisch auf Normalnull (NN) umgerechnet, sofern das Gerät '
          'das unterstützt (ab Android 14). Weicht sie trotzdem ab, kannst du sie auf '
          'der Start-Seite durch Antippen der Kachel "Höhe" an eine bekannte Höhe '
          'anpassen. Die Kachel muss dafür im gewählten Profil belegt sein '
          '(Einstellungen → Start).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        AutoHyphenatingText('Manueller Versatz: $offsetText'),
        if (offset != 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => widget.preferences.setAltitudeManualOffsetMeters(0),
              child: const Text('Versatz zurücksetzen'),
            ),
          ),
      ],
    );
  }

  /// Auswahl der Genauigkeits-/Aktualitätsstufe für die
  /// Geschwindigkeitsmessung, inkl. deutlichem Hinweis auf mögliche
  /// Auswirkungen auf den Akkuverbrauch.
  Widget _buildSpeedAccuracySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText(
          'Genauigkeit der Geschwindigkeitsmessung',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        // Deutlicher, dauerhaft sichtbarer Hinweis (nicht nur beiläufig in
        // einer Nebenzeile), dass sich die Wahl auf den Akkuverbrauch
        // auswirken kann - wie gefordert.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.battery_alert,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AutoHyphenatingText(
                  'Eine höhere Genauigkeit bzw. Aktualität kann den '
                  'Akkuverbrauch spürbar erhöhen. Eine Änderung wirkt sich '
                  'beim nächsten Öffnen der Tacho-Seite aus.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // NEU: DropdownButtonFormField statt RadioGroup/RadioListTile -
        // spart auf dem "Erweitert"-Tab deutlich Platz gegenüber einer
        // ausgeschriebenen Liste aller drei Optionen samt Beschreibung.
        // Nur die Beschreibung der AKTUELL gewählten Stufe wird darunter
        // angezeigt (statt aller drei gleichzeitig) - reicht aus, da die
        // übrigen Beschreibungen erst nach dem Aufklappen sichtbar sind.
        DropdownButtonFormField<SpeedAccuracyMode>(
          initialValue: widget.preferences.speedAccuracyMode,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          // Bewusst normales Text-Widget statt AutoHyphenatingText - siehe
          // dieselbe, bereits mehrfach im Projekt dokumentierte
          // Einschränkung bei SegmentedButton (README Abschnitt 13):
          // intrinsische Breitenberechnung verträgt sich nicht mit
          // AutoHyphenatingTexts LayoutBuilder-Ansatz. Bei den kurzen
          // Bezeichnungen wäre eine Silbentrennung ohnehin nie nötig.
          items: [
            for (final mode in SpeedAccuracyMode.values) DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (selected) {
            if (selected != null) widget.preferences.setSpeedAccuracyMode(selected);
          },
        ),
        const SizedBox(height: 8),
        AutoHyphenatingText(
          widget.preferences.speedAccuracyMode.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Auswahl, nach welcher Wartezeit eine anhaltend pausierte Track-
  /// Aufzeichnung per Benachrichtigung in Erinnerung gerufen wird - siehe
  /// README Abschnitt 22/39. Zaehlrad in Minuten, 0 = Erinnerung aus,
  /// Standard 3 Minuten.
  Widget _buildAutoPauseReminderSection(BuildContext context) {
    final minutes = widget.preferences.autoPauseReminderMinutes;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AutoHyphenatingText(
          'Erinnerung bei pausierter Track-Aufzeichnung',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.battery_alert,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AutoHyphenatingText(
                  'Bleibt eine Track-Aufzeichnung (z. B. durch erkannten '
                  'Stillstand) über die gewählte Zeit hinweg ununterbrochen '
                  'pausiert, erinnert eine Benachrichtigung daran, sie zu '
                  'beenden oder fortzusetzen.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Bewusst normales Text-Widget in den Zaehlrad-Eintraegen statt
        // AutoHyphenatingText (siehe README Abschnitt 13).
        SizedBox(
          height: 150,
          child: CupertinoPicker(
            scrollController: _reminderWheelController,
            itemExtent: 40,
            useMagnifier: true,
            magnification: 1.15,
            onSelectedItemChanged: (value) => widget.preferences.setAutoPauseReminderMinutes(value),
            children: [
              for (var i = 0; i <= _maxReminderMinutes; i++)
                Center(
                  child: Text(
                    i == 0 ? 'Aus' : '$i min',
                    style: TextStyle(fontSize: 22, color: textColor),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AutoHyphenatingText(
          minutes == 0
              ? 'Keine Erinnerung - eine Pause kann beliebig lange bestehen bleiben.'
              : 'Erinnert nach $minutes ${minutes == 1 ? 'Minute' : 'Minuten'} '
                  'ununterbrochener Pause.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
