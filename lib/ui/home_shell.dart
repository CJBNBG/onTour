import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';

import '../services/app_preferences.dart';
import '../services/track_recording_service.dart';
import 'compass_page.dart';
import 'info_page.dart';
import 'settings_page.dart';
import 'speed_page.dart';
import 'track_page.dart';

/// Rahmen der App: obere App-Leiste (mit Seitentitel und Info-Button) sowie
/// untere Navigationsleiste zum Wechseln zwischen den vier
/// Darstellungsseiten (Tacho / Kompass / Track / Einstellungen).
///
/// WICHTIG: Die jeweils sichtbare Seite wird bewusst NICHT über einen
/// IndexedStack im Hintergrund weiterlaufen gelassen, sondern beim
/// Tab-Wechsel disposed und bei erneutem Aufruf neu erzeugt. Dadurch
/// werden GPS-/Kompass-/Bewegungssensoren zuverlässig gestoppt, sobald die
/// jeweilige Seite nicht sichtbar ist - das spart spürbar Akku UND sorgt
/// dafür, dass eine geänderte Genauigkeitsstufe (siehe SpeedPage) beim
/// nächsten Aufruf automatisch greift.
///
/// AUSNAHME davon ist [_trackRecordingService]: Dieser wird bewusst NICHT
/// pro Seitenaufruf neu erzeugt, sondern hier in HomeShell einmalig
/// gehalten und an TrackPage durchgereicht (siehe Kommentar dort sowie in
/// TrackRecordingService) - eine laufende Track-Aufzeichnung darf nicht
/// abbrechen, nur weil zwischenzeitlich ein anderer Tab betrachtet wird.
///
/// HINWEIS zur frueheren eigenstaendigen Kartenseite: Die einstige
/// "Karte"-Seite (reine Live-Positionsanzeige ohne weiteren Kontext,
/// vormals map_page.dart) wurde entfernt - ihre Kartenfunktion steckt nun
/// direkt in TrackPage (Aufzeichnung) sowie in TrackDetailPage
/// (Detailansicht eines gespeicherten Tracks, per Navigator.push von der
/// Track-Liste in TrackPage aus erreichbar). Siehe README Abschnitt 9.
///
/// HINWEIS zur Begrifflichkeit: Was frueher "Route" hiess (Seite, Modelle,
/// Services, Anzeigetexte), heisst seit einer spaeteren Ueberarbeitung
/// durchgaengig "Track" (siehe README Abschnitt 19) - Dateien, Klassen und
/// Variablen wurden entsprechend umbenannt.
class HomeShell extends StatefulWidget {
  final AppPreferences preferences;

  const HomeShell({super.key, required this.preferences});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Start-Tab ist bewusst "Tacho" (Index 0), da sie die Hauptfunktion der
  // App darstellt und deshalb auch als Erstes in der Navigationsleiste
  // steht.
  int _selectedIndex = 0;

  // Siehe Klassenkommentar: lebt bewusst so lange wie HomeShell selbst,
  // nicht nur so lange wie die jeweils sichtbare TrackPage.
  final TrackRecordingService _trackRecordingService = TrackRecordingService();

  static const _titles = ['Tacho', 'Kompass', 'Track', 'Einstellungen'];

  @override
  void dispose() {
    // Nur hier (App/HomeShell wird komplett beendet) darf der Service
    // endgueltig geschlossen werden - siehe TrackRecordingService.dispose.
    unawaited(_trackRecordingService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Eine gemeinsame AppBar für alle vier Seiten sorgt zum einen dafür,
      // dass der Inhalt nie in den oberen Systembereich (Uhrzeit/Akku/
      // Empfang) hineinragt - Scaffold+AppBar respektieren diesen Bereich
      // automatisch -, zum anderen liefert sie auf jeder Seite denselben
      // Info-Button oben rechts.
      appBar: AppBar(
        title: AutoHyphenatingText(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Info',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const InfoPage()),
            ),
          ),
        ],
      ),
      body: _buildPage(_selectedIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Tacho'),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Kompass'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Track'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Einstellungen'),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return SpeedPage(preferences: widget.preferences);
      case 1:
        return const CompassPage();
      case 2:
        return TrackPage(
          recordingService: _trackRecordingService,
          preferences: widget.preferences,
        );
      case 3:
        return SettingsPage(preferences: widget.preferences);
      default:
        return const SizedBox.shrink();
    }
  }
}
