import 'map_style.dart';

/// Wählbares Overlay über der Basiskarte: ausgeschilderte Wander- bzw.
/// Radrouten (Waymarked Trails, siehe README Abschnitt 52) oder Seemarken
/// (OpenSeaMap, seit README Abschnitt 60 gleichberechtigt in derselben
/// Liste). Gegenseitig ausschließend ([none], [hiking], [cycling],
/// [seamarks]), damit die Karte übersichtlich bleibt.
///
/// Der Typname ist aus historischen Gründen noch "RouteOverlay" (er stammt
/// aus der Zeit, als es nur Routen gab) - fachlich ist es das
/// "Einblenden"-Overlay der Karte.
enum RouteOverlay {
  none(
    label: 'Aus',
    description: 'Nichts zusätzlich über der Karte einblenden.',
  ),

  hiking(
    label: 'Wanderrouten',
    description: 'Markierte Wander- und Fernwanderwege als farbige Linien.',
    urlTemplate: 'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
    maxNativeZoom: 18,
    attributions: [
      MapAttribution('Routen: Waymarked Trails (CC-BY-SA)', 'https://waymarkedtrails.org'),
    ],
    creditsLine: 'Routen-Overlay: Waymarked Trails (waymarkedtrails.org, Sarah '
        'Hoffmann), Lizenz CC-BY-SA. Daten: © OpenStreetMap-Mitwirkende.',
    usageNote: 'Kostenloser Dienst eines Einzelprojekts - bitte zurückhaltend '
        'nutzen, kein Massen-Download.',
    infoUrl: 'https://hiking.waymarkedtrails.org',
    legendUrl: 'https://hiking.waymarkedtrails.org',
    legendHints: [
      'Ausgeschilderte Wanderrouten aus OpenStreetMap als farbige Linien über '
          'der Karte.',
    ],
  ),

  cycling(
    label: 'Radrouten',
    description: 'Ausgeschilderte Radwege und Radfernwege als farbige Linien.',
    urlTemplate: 'https://tile.waymarkedtrails.org/cycling/{z}/{x}/{y}.png',
    maxNativeZoom: 18,
    attributions: [
      MapAttribution('Routen: Waymarked Trails (CC-BY-SA)', 'https://waymarkedtrails.org'),
    ],
    creditsLine: 'Routen-Overlay: Waymarked Trails (waymarkedtrails.org, Sarah '
        'Hoffmann), Lizenz CC-BY-SA. Daten: © OpenStreetMap-Mitwirkende.',
    usageNote: 'Kostenloser Dienst eines Einzelprojekts - bitte zurückhaltend '
        'nutzen, kein Massen-Download.',
    infoUrl: 'https://cycling.waymarkedtrails.org',
    legendUrl: 'https://cycling.waymarkedtrails.org',
    legendHints: [
      'Ausgeschilderte Radrouten aus OpenStreetMap als farbige Linien über '
          'der Karte.',
    ],
  ),

  seamarks(
    label: 'Seemarken',
    description: 'Bojen, Leuchttürme und Fahrwassermarkierungen (OpenSeaMap). '
        'Keine amtliche Seekarte, keine Tiefenangaben.',
    urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
    maxNativeZoom: 18,
    attributions: [
      MapAttribution('Seemarken: © OpenSeaMap-Mitwirkende', 'https://www.openseamap.org'),
    ],
    creditsLine: 'Seemarken-Overlay: OpenSeaMap (www.openseamap.org), '
        '© OpenSeaMap-Mitwirkende. Daten: © OpenStreetMap-Mitwirkende.',
    usageNote: 'Kostenloser Dienst eines Gemeinschaftsprojekts - bitte '
        'zurückhaltend nutzen, kein Massen-Download.',
    infoUrl: 'https://www.openseamap.org',
    legendUrl: 'https://www.openseamap.org',
    legendHints: [
      'Bojen, Leuchttürme und Fahrwassermarkierungen über der Karte - keine '
          'amtliche Seekarte, keine Tiefenangaben.',
    ],
  ),
  camping(
    label: 'Camping und Stellplätze',
    description: 'Campingplätze und Wohnmobil-Stellplätze als antippbare '
        'Marker ab Zoomstufe 9, optional auch einfache Zeltplätze.',
    attributions: [
      MapAttribution(
        'Camping: OpenCampingMap, © OpenStreetMap-Mitwirkende',
        'https://opencampingmap.org',
      ),
    ],
    creditsLine: 'Camping- und Stellplatzdaten: OpenCampingMap '
        '(opencampingmap.org, Sven Geggus). Daten: © OpenStreetMap-Mitwirkende (ODbL).',
    usageNote: 'Die Daten sind in der App enthalten und lassen sich auf der Start-Seite oder in den '
        'Einstellungen (Karten) aktualisieren. Sie können veraltet oder '
        'unvollständig sein. Fehlende Angaben lassen sich in '
        'OpenStreetMap nachtragen.',
    infoUrl: 'https://opencampingmap.org',
    legendUrl: 'https://opencampingmap.org',
  );

  final String label;
  final String description;

  /// Kachel-URL-Schablone - null bei [none].
  final String? urlTemplate;

  /// Höchste Zoomstufe mit echten Kacheln (darüber vergrößert) - je Overlay
  /// einzeln einstellbar, analog zu MapStyle.maxNativeZoom.
  final int maxNativeZoom;

  final List<MapAttribution> attributions;
  final String creditsLine;
  final String usageNote;
  final String infoUrl;

  /// Seite des Anbieters (Legende) und kurze Hinweise für die Legende in
  /// der App (siehe MapLegendButton).
  final String legendUrl;
  final List<String> legendHints;

  const RouteOverlay({
    required this.label,
    required this.description,
    this.urlTemplate,
    this.maxNativeZoom = 18,
    this.attributions = const [],
    this.creditsLine = '',
    this.usageNote = '',
    this.infoUrl = '',
    this.legendUrl = '',
    this.legendHints = const [],
  });

  bool get isActive => this != RouteOverlay.none;
}
