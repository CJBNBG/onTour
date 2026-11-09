import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/map_style.dart';
//import '../models/route_overlay.dart';
import '../services/diagnostic_log_service.dart';

/// Eine von der App verwendete Berechtigung samt Begründung (siehe
/// [_permissions], README Abschnitt 62).
class _PermissionInfo {
  final String title;
  final String technicalName;
  final String reason;

  const _PermissionInfo(this.title, this.technicalName, this.reason);
}

/// Info-Seite: Programmautor, App-Name, App-Version sowie ein Zugang zur
/// Übersicht aller verwendeten Module (Flutters eingebaute Lizenzseite).
/// Über den Info-Button in der App-Leiste von jeder
/// Hauptseite aus erreichbar (siehe HomeShell).
class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  static const _authorName = 'Claus J. Bauer';

  /// Alle in der AndroidManifest.xml angeforderten Berechtigungen mit
  /// Begründung - bei Änderungen am Manifest hier nachziehen.
  static const List<_PermissionInfo> _permissions = [
    _PermissionInfo(
      'Standort (genau und ungefähr)',
      'ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION',
      'Grundlage fast aller Funktionen: Tempo, Kurs, Höhe und Position, '
          'Track-Aufzeichnung samt Karte, Anzahl der Satelliten und die '
          'Korrektur des Kompasses auf geografisch Nord (Missweisung). Android '
          'fragt beide Stufen gemeinsam ab; die App nutzt die genaue Position. '
          'Die Abfrage erscheint beim ersten Öffnen einer dieser Funktionen.',
    ),
    _PermissionInfo(
      'Vordergrunddienst für Standort',
      'FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION',
      'Damit eine Track-Aufzeichnung weiterläuft, wenn die App im Hintergrund '
          'ist oder das Display ausgeht (z. B. während eine Navigations-App '
          'geöffnet ist). Der Dienst läuft nur während der Aufzeichnung und '
          'zeigt dafür eine dauerhafte Benachrichtigung. Standortzugriff im '
          'Hintergrund (ACCESS_BACKGROUND_LOCATION) benötigt die App nicht.',
    ),
    _PermissionInfo(
      'Benachrichtigungen',
      'POST_NOTIFICATIONS (ab Android 13)',
      'Für den Hinweis "onTour zeichnet auf" während einer Aufzeichnung und '
          'für die Erinnerung, wenn eine Aufzeichnung lange pausiert ist. Ohne '
          'diese Berechtigung läuft die Aufzeichnung weiter, aber ohne sichtbaren '
          'Hinweis.',
    ),
    _PermissionInfo(
      'Gerät wachhalten',
      'WAKE_LOCK',
      'Hält während einer Aufzeichnung die CPU wach, damit keine Positionen '
          'verloren gehen. Wird bei der Installation automatisch erteilt und '
          'nicht abgefragt.',
    ),
    _PermissionInfo(
      'Internet',
      'INTERNET',
      'Zum Laden der Kartenkacheln (OpenStreetMap und die weiteren wählbaren '
          'Karten und Overlays) und für die Ortssuche. Bereits angezeigte '
          'Kartenausschnitte werden zwischengespeichert und sind danach auch '
          'ohne Netz sichtbar. Wird bei der Installation automatisch erteilt.',
    ),
  ];

  /// Link zur Play-Store-Entwicklerseite (Liste aller Apps des Autors) -
  /// siehe README Abschnitt 45. LEER lassen, solange der Link nicht
  /// eingetragen ist: Dann wird der Button gar nicht erst angezeigt.
  /// Format z. B. 'https://play.google.com/store/apps/dev?id=1234567890123456789'
  /// bzw. 'https://play.google.com/store/apps/developer?id=Name'.
  static const _playStoreDeveloperUrl = 'https://play.google.com/store/apps/developer?id=CJBNBG';

  Future<void> _openPlayStoreDeveloperPage() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(_playStoreDeveloperUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Play Store konnte nicht geöffnet werden.')),
      );
    }
  }

  // FEHLERKORREKTUR: DiagnosticLogService hat seit der Umstellung auf ein
  // Singleton (siehe README Abschnitt 34) nur noch einen privaten
  // Konstruktor - Zugriff ausschließlich über die statische Instanz
  // DiagnosticLogService.instance, nicht mehr per DiagnosticLogService().
  final DiagnosticLogService _diagnosticLogService = DiagnosticLogService.instance;

  PackageInfo? _packageInfo;

  /// NEU (siehe README Abschnitt 31): true, sobald eine nicht-leere
  /// Diagnose-Log-Datei existiert - in einem Release-Build (Play Store)
  /// immer false, da die Aufzeichnung dort gar nicht erst startet (siehe
  /// OnTourApplication), der Button erscheint dementsprechend nur in
  /// Debug-/Test-Builds.
  bool _hasDiagnosticLog = false;

  @override
  void initState() {
    super.initState();
    // PackageInfo.fromPlatform() darf laut Paket-Dokumentation nicht VOR
    // runApp() aufgerufen werden - hier (in initState einer bereits
    // laufenden Seite) ist das unproblematisch.
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _packageInfo = info);
    });
    _diagnosticLogService.hasLog().then((hasLog) {
      if (!mounted) return;
      setState(() => _hasDiagnosticLog = hasLog);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _packageInfo;

    return Scaffold(
      appBar: AppBar(title: AutoHyphenatingText('Info')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Zeigt das tatsächliche App-Icon (dieselbe Bilddatei, aus der
            // auch das Launcher-Icon erzeugt wird, siehe README Abschnitt
            // 14) statt eines generischen Material-Icons - dafür muss
            // assets/icon/icon.png in pubspec.yaml unter flutter/assets
            // eingetragen sein UND die App nach der pubspec-Änderung
            // vollständig neu gestartet werden (ein reines Hot Reload
            // bindet neu deklarierte Assets nicht ein - Hot Restart oder
            // kompletter Neustart ist hier nötig).
            //
            // WICHTIG (Absturzschutz): errorBuilder fängt den Fall ab,
            // dass die Asset-Datei zur Laufzeit trotzdem nicht gefunden
            // wird (z. B. abweichender Dateiname/Pfad im jeweiligen
            // Projekt oder eine pubspec-Änderung ohne vorherigen
            // Neustart) - statt einer abstürzenden Exception erscheint
            // dann einfach das bisherige, generische Icon als Fallback.
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 96,
                height: 96,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.explore,
                  size: 96,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            AutoHyphenatingText(
              info?.appName ?? 'onTour',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              info != null ? 'Version ${info.version} (Build ${info.buildNumber})' : 'Version wird geladen …',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: AutoHyphenatingText('Programmautor'),
              subtitle: AutoHyphenatingText(_authorName),
            ),
            if (_playStoreDeveloperUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _openPlayStoreDeveloperPage,
                  icon: const Icon(Icons.storefront_outlined),
                  label: AutoHyphenatingText('Meine Apps im Play Store'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            AutoHyphenatingText(
              'Diese App verwendet mehrere Open-Source-Module. Die '
              'jeweiligen Lizenztexte lassen sich hier einsehen:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: info?.appName ?? 'onTour',
                applicationVersion: info?.version,
                applicationLegalese: '© ${DateTime.now().year} $_authorName',
              ),
              icon: const Icon(Icons.description_outlined),
              label: AutoHyphenatingText('Verwendete Module'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            AutoHyphenatingText('Berechtigungen', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              'Diese Berechtigungen verwendet onTour und aus diesen Gründen:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final permission in _permissions) ...[
              AutoHyphenatingText(permission.title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              AutoHyphenatingText(
                permission.technicalName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 2),
              AutoHyphenatingText(permission.reason, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            AutoHyphenatingText(
              'Keine Berechtigung brauchen die Sensoren für Kompass '
              '(Magnetfeld), Bewegungserkennung (Beschleunigung, Drehrate) und '
              'Luftdruck sowie das Importieren und Teilen von GPX-Dateien (läuft '
              'über die Systemdialoge). onTour betreibt keinen eigenen Server und '
              'sendet keine Positionsdaten dorthin; beim Laden der Karte und bei '
              'der Ortssuche werden aber Anfragen an die jeweiligen Kartendienste '
              'gestellt (Kartenausschnitt bzw. Suchbegriff).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // NEU (README Abschnitt 51): Kartenquellen und Lizenzen - u. a.
            // Voraussetzung der Lizenz der Reit- und Wanderkarte.
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            AutoHyphenatingText('Kartenmaterial', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final style in MapStyle.values) ...[
              AutoHyphenatingText(style.label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              AutoHyphenatingText(style.creditsLine, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
            AutoHyphenatingText(
              'Wander- und Radrouten (optionales Overlay): Waymarked Trails '
              '(waymarkedtrails.org, Sarah Hoffmann), CC-BY-SA.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            AutoHyphenatingText(
              'Seemarken (optionales Overlay): © OpenSeaMap-Mitwirkende.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // NEU (siehe README Abschnitt 31): Nur sichtbar, wenn
            // tatsächlich eine Diagnose-Log-Datei existiert - das ist nur
            // in Debug-/Test-Builds der Fall (siehe OnTourApplication),
            // in einem Release-Build für den Play Store bleibt dieser
            // gesamte Abschnitt unsichtbar.
            if (_hasDiagnosticLog) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              AutoHyphenatingText(
                'Zur Fehlersuche zeichnet diese Test-Version fortlaufend ein '
                'technisches Diagnose-Protokoll auf. Es kann u. a. '
                'GPS-Positionen und andere technische Daten enthalten - '
                'bitte nur weitergeben, wenn du gezielt bei der Fehlersuche '
                'unterstützen möchtest.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _diagnosticLogService.shareLog(),
                icon: const Icon(Icons.bug_report_outlined),
                label: AutoHyphenatingText('Diagnose-Protokoll exportieren'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
