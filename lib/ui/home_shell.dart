import 'dart:async';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_preferences.dart';
import '../services/pressure_trend_service.dart';
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
///
/// NEU (siehe README Abschnitt 23): Antippen der Erinnerungs-
/// Benachrichtigung für eine anhaltend pausierte Aufzeichnung (siehe
/// Abschnitt 22) soll direkt zum Track-Tab führen, da dort die
/// zugehörigen Bedienelemente (Fortsetzen/Beenden) liegen. Dafür fragt
/// [_checkPendingNavigation] bei jedem Start UND bei jedem Zurückkehren
/// in den Vordergrund (`AppLifecycleState.resumed`) über einen
/// MethodChannel bei der nativen Seite nach, ob ein solcher
/// Navigationswunsch vorliegt ("Pull"-Modell) - siehe dortiger Kommentar
/// für die Begründung, warum kein "Push" von nativ nach Dart verwendet
/// wird.
class HomeShell extends StatefulWidget {
  final AppPreferences preferences;

  const HomeShell({super.key, required this.preferences});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Start-Tab ist bewusst "Tacho" (Index 0), da sie die Hauptfunktion der
  // App darstellt und deshalb auch als Erstes in der Navigationsleiste
  // steht.
  int _selectedIndex = 0;

  /// Index des Track-Tabs - als benannte Konstante, damit
  /// [_checkPendingNavigation] nicht mit einer "magischen" 2 arbeitet.
  static const _trackTabIndex = 2;

  // Siehe Klassenkommentar: lebt bewusst so lange wie HomeShell selbst,
  // nicht nur so lange wie die jeweils sichtbare TrackPage.
  final TrackRecordingService _trackRecordingService = TrackRecordingService();

  /// NEU (siehe README Abschnitt 47): Luftdruck-Verlauf für den
  /// 3-Stunden-Trend - lebt wie der TrackRecordingService bewusst so lange
  /// wie HomeShell, da ein Trend den Verlauf über Stunden braucht, der bei
  /// jedem Seitenwechsel sonst verloren ginge.
  final PressureTrendService _pressureTrendService = PressureTrendService();

  static const _titles = ['Tacho', 'Kompass', 'Track', 'Einstellungen'];

  /// Siehe Klassenkommentar (Abschnitt 23) - Methodenname auf nativer
  /// Seite muss exakt übereinstimmen (OnTourApplication.kt).
  static const MethodChannel _navigationChannel = MethodChannel('ontour/navigation');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // NEU (README Abschnitt 47): Startet die fortlaufende Luftdruck-
    // Aufzeichnung (lädt zuvor einen ggf. gesicherten Verlauf).
    unawaited(_pressureTrendService.start());
    // Deckt den Fall ab, dass die App durch Antippen der Erinnerungs-
    // Benachrichtigung frisch gestartet wurde (siehe Abschnitt 23).
    _checkPendingNavigation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Deckt den Fall ab, dass die App bereits lief (Activity existierte
    // noch) und lediglich per Benachrichtigung in den Vordergrund geholt
    // wurde - HomeShell.initState läuft in diesem Fall NICHT erneut,
    // wohl aber dieser Lifecycle-Callback.
    if (state == AppLifecycleState.resumed) {
      _checkPendingNavigation();
    }
  }

  Future<void> _checkPendingNavigation() async {
    bool shouldOpenTrackTab;
    try {
      shouldOpenTrackTab =
          await _navigationChannel.invokeMethod<bool>('consumePendingOpenTrackTab') ?? false;
    } catch (_) {
      // Reiner Komfort-Zusatz (siehe Abschnitt 23) - ein Fehlschlag (z. B.
      // auf einer Plattform ohne die native Implementierung) darf die
      // App nicht beeinträchtigen.
      return;
    }
    if (shouldOpenTrackTab && mounted) {
      setState(() => _selectedIndex = _trackTabIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Nur hier (App/HomeShell wird komplett beendet) darf der Service
    // endgueltig geschlossen werden - siehe TrackRecordingService.dispose.
    unawaited(_trackRecordingService.dispose());
    unawaited(_pressureTrendService.dispose());
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
        return CompassPage(
          preferences: widget.preferences,
          pressureService: _pressureTrendService,
        );
      case _trackTabIndex:
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
