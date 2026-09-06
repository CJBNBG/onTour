import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';

import '../models/speed_accuracy_mode.dart';
import '../services/app_preferences.dart';

/// Einstellungsseite: Anzeigemodus (System/Dark/Light) sowie die
/// Genauigkeits-/Aktualitätsstufe der Geschwindigkeitsmessung.
class SettingsPage extends StatelessWidget {
  final AppPreferences preferences;

  const SettingsPage({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
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
              selected: {preferences.themeMode},
              onSelectionChanged: (selection) {
                preferences.setThemeMode(selection.first);
              },
            ),
          ),
          const SizedBox(height: 32),
          _buildSpeedAccuracySection(context),
        ],
      ),
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
        // RadioGroup fasst mehrere Radio-Widgets (hier: die RadioListTiles
        // der einzelnen Genauigkeitsstufen) zusammen und stellt Auswahl-
        // wert (groupValue) sowie Änderungs-Callback (onChanged) zentral
        // bereit - die einzelnen RadioListTiles bekommen dadurch nur noch
        // ihren jeweiligen value. Das ersetzt die früheren, mittlerweile
        // deprecateten groupValue-/onChanged-Parameter direkt an
        // RadioListTile.
        RadioGroup<SpeedAccuracyMode>(
          groupValue: preferences.speedAccuracyMode,
          onChanged: (selected) {
            if (selected != null) preferences.setSpeedAccuracyMode(selected);
          },
          child: Column(
            children: [
              for (final mode in SpeedAccuracyMode.values)
                RadioListTile<SpeedAccuracyMode>(
                  value: mode,
                  title: AutoHyphenatingText(mode.label),
                  subtitle: AutoHyphenatingText(mode.description),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
