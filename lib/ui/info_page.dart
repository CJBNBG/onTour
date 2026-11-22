import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:ontour/services/camping_data_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/map_style.dart';
import '../models/speed_unit.dart';
//import '../models/route_overlay.dart';
import '../services/diagnostic_log_service.dart';
import '../util/navigation_notice.dart';
import '../util/track_formatter.dart';

/// Eine von der App verwendete Berechtigung samt Begründung (siehe
/// [_permissions], README Abschnitt 62/66).
class _PermissionInfo {
  final String title;
  final String reason;

  const _PermissionInfo(this.title, this.reason);
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

  /// Alle in der AndroidManifest.xml angeforderten Berechtigungen, in
  /// einfacher Sprache begründet (README Abschnitt 66) - bei Änderungen am
  /// Manifest hier nachziehen. Die technischen Namen stehen bewusst nicht
  /// in der App (siehe README Abschnitt 62).
  static const List<_PermissionInfo> _permissions = [
    _PermissionInfo(
      'Standort',
      'Ohne Standort weiß onTour nicht, wo du bist. Er wird gebraucht für '
          'Tempo, Höhe, Position und Kurs, für die Karte mit deinem Standpunkt '
          'und für die Aufzeichnung deiner Strecke. Android fragt dabei nach '
          '"genau" und "ungefähr". onTour braucht die genaue Angabe, sonst '
          'wären Tempo und Strecke zu ungenau.',
    ),
    _PermissionInfo(
      'Aufzeichnung im Hintergrund',
      'Wenn du eine Strecke aufzeichnest und zwischendurch eine andere App '
          'benutzt oder das Display ausgeht, soll die Aufzeichnung '
          'weiterlaufen. Dafür darf onTour im Hintergrund weiterarbeiten. Du '
          'erkennst das an einer Meldung in der Statusleiste. Das geschieht nur '
          'während einer Aufzeichnung. Sonst nutzt onTour deinen Standort nur, '
          'solange die App geöffnet ist.',
    ),
    _PermissionInfo(
      'Benachrichtigungen',
      'Damit du siehst, dass eine Aufzeichnung läuft, und damit onTour dich '
          'erinnern kann, wenn eine Aufzeichnung lange pausiert ist. Ohne diese '
          'Erlaubnis läuft die Aufzeichnung trotzdem, aber ohne Hinweis.',
    ),
    _PermissionInfo(
      'Gerät wach halten',
      'Während einer Aufzeichnung soll das Gerät nicht in den Tiefschlaf '
          'fallen, damit keine Punkte deiner Strecke verloren gehen. Diese '
          'Erlaubnis erteilt Android automatisch. Du musst nichts bestätigen.',
    ),
    _PermissionInfo(
      'Körperliche Aktivität (Schritte)',
      'Für den Schrittzähler. Android zählt die Schritte über einen eigenen '
          'Sensor und verlangt dafür diese Erlaubnis. onTour fragt erst, wenn '
          'die Kachel "Schritte" auf der Start-Seite angetippt wird. Ohne die '
          'Erlaubnis gibt es keine Schrittzahl, auch nicht in einer Track-Aufzeichnung. '
          'Damit die Tageszahl stimmt, merkt sich onTour um Mitternacht kurz '
          'den Zählerstand und setzt dafür nach einem Neustart des Geräts '
          'einen Zeitgeber neu. Außer dass sie mit einer Trackaufzeichnung '
          'exportiert werden kann, bleibt die ermittelte Anzahl Schritte '
          'auf deinem Gerät.',
    ),
    _PermissionInfo(
      'Internet',
      'Für die Kartenbilder und die Ortssuche. Kartenausschnitte, die du '
          'schon angesehen hast, merkt sich die App und zeigt sie auch ohne '
          'Netz. Deine Strecken und Positionen bleiben auf deinem Gerät. Bei '
          'den Kartenanbietern wird nur das gewünschte Kartengebiet abgefragt, '
          'bei der Ortssuche der Suchbegriff.',
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

  /// Umrechnungsfaktoren für den Abschnitt "Umrechnungsfaktoren" (README
  /// Abschnitt 69). Die Werte werden aus denselben Konstanten gebildet, mit
  /// denen die App rechnet (SpeedUnit, TrackFormatter) - Anzeige und
  /// Berechnung können so nicht auseinanderlaufen.
  static List<(String, String)> _conversionRows() {
    final factor = NumberFormat('0.#####', 'de_DE');
    String perMs(SpeedUnit unit) => factor.format(unit.fromMetersPerSecond(1));
    final nauticalMileMeters = TrackFormatter.metersPerNauticalMile;
    return [
      ('1 m/s', '= ${perMs(SpeedUnit.kilometersPerHour)} km/h'),
      ('1 m/s', '= ${perMs(SpeedUnit.knots)} kn'),
      ('1 m/s', '= ${perMs(SpeedUnit.milesPerHour)} mph'),
      (
        '1 Seemeile (sm)',
        '= ${NumberFormat('0', 'de_DE').format(nauticalMileMeters)} m = '
            '${factor.format(nauticalMileMeters / 1000)} km',
      ),
      ('1 Knoten (kn)', '= 1 sm pro Stunde'),
      ('1 Meile (mi, für mph)', '= 1.609,344 m'),
      ('1 Grad (°)', '= 60 Minuten (\') = 3600 Sekunden (")'),
    ];
  }

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
            // NEU (README Abschnitt 70/71): Derselbe Hinweis wie beim ersten
            // Start, hier jederzeit nachlesbar - aus Platzgründen ein- und
            // ausklappbar und beim Öffnen der Seite immer eingeklappt.
            Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                return Card(
                  color: scheme.errorContainer,
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  // Entfernt die Trennlinien, die ExpansionTile sonst ober-
                  // und unterhalb des Inhalts zeichnet.
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      iconColor: scheme.onErrorContainer,
                      collapsedIconColor: scheme.onErrorContainer,
                      textColor: scheme.onErrorContainer,
                      collapsedTextColor: scheme.onErrorContainer,
                      leading: Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                      // Bewusst normales Text-Widget (kurzer Einzeiler).
                      title: const Text(NavigationNotice.title),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final paragraph in NavigationNotice.paragraphs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: AutoHyphenatingText(
                              paragraph,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onErrorContainer,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
              'Diese Erlaubnisse braucht onTour und aus diesen Gründen:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final permission in _permissions) ...[
              AutoHyphenatingText(permission.title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              AutoHyphenatingText(permission.reason, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            AutoHyphenatingText(
              'Keine Erlaubnis brauchen die Sensoren deines Geräts (Kompass, '
              'Bewegung, Luftdruck) und das Speichern oder Teilen von Strecken '
              'als Datei. Das läuft über die normalen Android-Fenster. onTour '
              'greift nicht auf Kontakte, Fotos, Kamera, Mikrofon oder '
              'Nachrichten zu.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            AutoHyphenatingText('Umrechnungsfaktoren', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            AutoHyphenatingText(
              'Alle Messwerte speichert onTour in Metern und Metern pro '
              'Sekunde und rechnet sie erst für die Anzeige um - mit diesen '
              'Faktoren:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final row in _conversionRows())
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: AutoHyphenatingText(row.$1, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    Expanded(
                      flex: 6,
                      child: AutoHyphenatingText(row.$2, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
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
            const SizedBox(height: 10),
            AutoHyphenatingText(
              'Camping- und Stellplatzdaten: OpenCampingMap (opencampingmap.org, Sven Geggus), Daten © OpenStreetMap-Mitwirkende (ODbL), Stand: ${CampingDataService.instance.dataDateText}.',
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
