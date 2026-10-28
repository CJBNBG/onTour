import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/position_display_format.dart';
import '../models/speed_display_style.dart';
import '../models/speed_accuracy_mode.dart';
import '../services/app_preferences.dart';

/// Einstellungsseite, unterteilt in zwei Unterreiter (NEU, siehe README
/// Abschnitt 24):
/// - **Anzeige**: Anzeigemodus (System/Dark/Light) - die Einstellung, die
///   am ehesten "im Vorbeigehen" angepasst wird.
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
  late final TabController _tabController = TabController(length: 2, vsync: this);

  /// Obergrenze der Pause-Erinnerung in Minuten (0 = aus).
  static const int _maxReminderMinutes = 120;

  late final FixedExtentScrollController _reminderWheelController =
      FixedExtentScrollController(initialItem: widget.preferences.autoPauseReminderMinutes);

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
              Tab(text: 'Anzeige'),
              Tab(text: 'Erweitert'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDisplayTab(context),
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
                label: Text('System'),
                icon: const Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Hell'),
                icon: const Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dunkel'),
                icon: const Icon(Icons.dark_mode),
              ),
            ],
            selected: {widget.preferences.themeMode},
            onSelectionChanged: (selection) {
              widget.preferences.setThemeMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 32),
        _buildSpeedDisplayStyleSection(context),
        const SizedBox(height: 32),
        _buildPositionDisplayFormatSection(context),
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
                label: Text('Digital'),
                icon: Icon(Icons.pin),
              ),
              ButtonSegment(
                value: SpeedDisplayStyle.analog,
                label: Text('Analog'),
                icon: Icon(Icons.speed),
              ),
            ],
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
            onSelectedItemChanged: (value) =>
                widget.preferences.setAutoPauseReminderMinutes(value),
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
