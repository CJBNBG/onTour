import 'map_style.dart';

/// Wählbares Routen-Overlay (Waymarked Trails) über der Basiskarte - zeigt
/// ausgeschilderte Wander- bzw. Radrouten als farbige Linien (siehe README
/// Abschnitt 52). Gegenseitig ausschließend ([none], [hiking], [cycling]),
/// damit die Karte übersichtlich bleibt. Unabhängig vom Seemarken-Overlay
/// (`AppPreferences.mapNauticalMode`).
enum RouteOverlay {
  none(
    label: 'Aus',
    description: 'Keine zusätzlichen Routen auf der Karte.',
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
        'nutzen, kein Massen-Download. Bei größerer Nutzerzahl den Betreiber '
        'kontaktieren.',
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
        'nutzen, kein Massen-Download. Bei größerer Nutzerzahl den Betreiber '
        'kontaktieren.',
    infoUrl: 'https://cycling.waymarkedtrails.org',
    legendUrl: 'https://cycling.waymarkedtrails.org',
    legendHints: [
      'Ausgeschilderte Radrouten aus OpenStreetMap als farbige Linien über '
          'der Karte.',
    ],
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

  bool get isActive => urlTemplate != null;
}
