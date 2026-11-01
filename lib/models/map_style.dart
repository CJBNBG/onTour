/// Ein Quellenhinweis (Text + Ziel-Link) für die Kartenanzeige.
class MapAttribution {
  final String text;
  final String url;

  const MapAttribution(this.text, this.url);
}

/// Wählbare Basiskarte der Kartenansichten (Track-Seite und
/// Track-Detailansicht), siehe README Abschnitt 51. Unabhängig davon lässt
/// sich das Seemarken-Overlay (OpenSeaMap, `AppPreferences.mapNauticalMode`)
/// über jede dieser Basiskarten legen.
///
/// WICHTIG (Lizenz/Nutzungsbedingungen): Jede Karte hat eigene Bedingungen,
/// die hier je Stil als Text hinterlegt sind (Anzeige in den Einstellungen
/// und auf der Info-Seite). Die Quellenangaben ([attributions]) müssen auf
/// der Karte sichtbar sein - bei der Reit- und Wanderkarte ist das
/// Voraussetzung der Lizenz und wird deshalb dauerhaft angezeigt
/// ([alwaysVisibleAttribution]).
enum MapStyle {
  standard(
    label: 'Standard (OpenStreetMap)',
    description: 'Allgemeine Straßen- und Ortskarte - Standardeinstellung.',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxNativeZoom: 19,
    attributions: [
      MapAttribution('© OpenStreetMap-Mitwirkende', 'https://www.openstreetmap.org/copyright'),
    ],
    creditsLine: 'Kartendaten und Darstellung: © OpenStreetMap-Mitwirkende (ODbL).',
    usageNote: 'Öffentlicher Server der OpenStreetMap Foundation. Es gilt deren '
        'Tile Usage Policy (u. a. kein Massen-Download von Kacheln).',
    infoUrl: 'https://operations.osmfoundation.org/policies/tiles/',
    legendUrl: 'https://wiki.openstreetmap.org/wiki/Standard_tile_layer/Key',
    legendHints: [
      'Allgemeine Straßen-, Orts- und Landnutzungskarte aus OpenStreetMap.',
    ],
  ),

  topPlusOpen(
    label: 'Deutschland-Referenzkarte (TopPlusOpen)',
    description: 'Amtliche, übersichtliche Webkarte des Bundesamts für '
        'Kartographie und Geodäsie - ruhige Darstellung, gut lesbar, '
        'weltweit mit Schwerpunkt Deutschland.',
    // Achtung: Reihenfolge {z}/{y}/{x} (Zeile vor Spalte), nicht {z}/{x}/{y}.
    urlTemplate:
        'https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web/default/WEBMERCATOR/{z}/{y}/{x}.png',
    maxNativeZoom: 18,
    // Quellenvermerk laut Nutzungsbedingungen: "© BKG (Jahr des letzten
    // Datenbezugs) dl-de/by-2-0, Datenquellen: (Link)". Das Jahr jährlich
    // prüfen (Datenstand siehe BKG-Dokumentation) und ggf. anpassen.
    attributions: [
      MapAttribution('© BKG (2026)', 'https://www.bkg.bund.de'),
      MapAttribution('dl-de/by-2-0', 'https://www.govdata.de/dl-de/by-2-0'),
      MapAttribution(
        'Datenquellen',
        'https://sgx.geodatenzentrum.de/web_public/gdz/datenquellen/datenquellen_topplusopen.html',
      ),
    ],
    creditsLine: 'TopPlusOpen: © Bundesamt für Kartographie und Geodäsie (BKG), '
        'Datenlizenz Deutschland - Namensnennung - Version 2.0 (dl-de/by-2-0). '
        'Datenquellen u. a. OpenStreetMap-Mitwirkende.',
    usageNote: 'Kostenlos nutzbar, ohne Schlüssel. Bedingung ist ein deutlich '
        'sichtbarer Quellenvermerk (wird dauerhaft angezeigt). Jährliche '
        'Aktualisierung.',
    infoUrl: 'https://gdz.bkg.bund.de/index.php/default/webdienste/topplusopen-produkte.html',
    legendUrl: 'https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/TopPlusOpen.pdf',
    legendHints: [
      'Ruhig gestaltete amtliche Referenzkarte, nicht auf Wanderwege oder '
          'Höhenlinien ausgelegt.',
      'Die Produktbeschreibung des BKG erläutert Inhalt und Aufbau der Karte.',
    ],
    alwaysVisibleAttribution: true,
  ),

  openTopoMap(
    label: 'Topografisch (OpenTopoMap-R)',
    description: 'Topografische Karte mit Höhenlinien und Geländedarstellung - '
        'gut geeignet für Wanderungen.',
    urlTemplate: 'https://tile.openmaps.fr/opentopomap/{z}/{x}/{y}.png',
    // Startwert - ggf. nach Test auf dem Gerät anpassen (jenseits dieser
    // Stufe werden die Kacheln nur vergrößert dargestellt, nicht leer).
    maxNativeZoom: 17,
    attributions: [
      MapAttribution('© OpenTopoMap-R', 'https://github.com/sletuffe/OpenTopoMap'),
      MapAttribution('❤️ Donation', 'https://openmaps.fr/donate'),
      MapAttribution('© OpenStreetMap-Mitwirkende', 'https://www.openstreetmap.org/copyright'),
    ],
    creditsLine: 'Kartenstil OpenTopoMap-R, bereitgestellt von openmaps.fr. '
        'Daten: © OpenStreetMap-Mitwirkende (ODbL).',
    usageNote: 'Kostenlos für nicht-kommerzielle Projekte. Festes Limit von '
        '500.000 Kacheln pro Monat, darüber wird der Zugriff eingeschränkt. '
        'Kein Massen-Download, kein Vorab-Laden. Der Zugriff kann ohne '
        'Vorankündigung gesperrt werden.',
    infoUrl: 'https://openmaps.fr/tile-usage-policy.html',
    legendUrl: 'https://opentopomap.org/about#legende',
    legendHints: [
      'Höhenlinien und Geländeschummerung.',
      'Symbole für markante Punkte wie Kirchen, Türme, Windkraftanlagen und '
          'herausragende Bäume.',
      'Die Legende der Original-OpenTopoMap gilt sinngemäß auch für die hier '
          'verwendete Variante OpenTopoMap-R.',
    ],
    // Die Policy verlangt eine ohne Antippen sichtbare Quellenangabe
    // (Stil, Spendenlink, OpenStreetMap).
    alwaysVisibleAttribution: true,
  ),

  hikingRiding(
    label: 'Reit- und Wanderkarte',
    description: 'Topografische Karte für Wanderer und Reiter mit Höhenlinien, '
        'Geländeschummerung und markierten Wanderwegen (Schwerpunkt '
        'Deutschland und Umgebung).',
    urlTemplate: 'https://topo.wanderreitkarte.de/topo/{z}/{x}/{y}.png',
    // Startwert - ggf. nach Test auf dem Gerät anpassen.
    maxNativeZoom: 17,
    attributions: [
      MapAttribution('Reit- und Wanderkarte', 'https://www.wanderreitkarte.de'),
      MapAttribution('CC-BY-NC-SA', 'https://creativecommons.org/licenses/by-nc-sa/3.0/de/'),
      MapAttribution('© OpenStreetMap-Mitwirkende', 'https://www.openstreetmap.org/copyright'),
    ],
    creditsLine: 'Reit- und Wanderkarte (www.wanderreitkarte.de), Lizenz '
        'CC-BY-NC-SA 3.0 DE. Daten von OpenStreetMap und Mitwirkenden, '
        'Höhendaten CIAT/NASA.',
    usageNote: 'Nur kostenlos und nicht-kommerziell nutzbar. Von '
        'werbefinanzierten oder gewerblichen Angeboten wird eine Beteiligung '
        'an den Serverkosten erwartet. Limit: 40.000 Kacheln pro Tag, kein '
        'Massen-Download - bei Überschreitung wird der Zugriff für 24 '
        'Stunden gesperrt.',
    infoUrl: 'https://www.wanderreitkarte.de/licence_de.php',
    legendUrl: 'https://www.wanderreitkarte.de/help_de.php',
    legendHints: [
      'Markierte Wanderwege sind weiß hinterlegt und tragen Schildchen mit der '
          'Wandermarkierung; farbige Kästchen zeigen die Hauptfarbe der '
          'Markierung.',
      'Reitwege und Reitrouten sind hellblau hinterlegt; amtlich '
          'ausgeschilderte Reitwege tragen das blaue Verkehrsschild.',
      'Die Anleitung des Anbieters enthält ein Video, das das Kartenbild '
          'erklärt.',
    ],
    alwaysVisibleAttribution: true,
  ),

  cyclOsm(
    label: 'Radkarte (CyclOSM)',
    description: 'Auf Radfahrer zugeschnittene Karte: Radwege, Radstreifen, '
        'Steigungen, Fahrradläden und Abstellanlagen.',
    urlTemplate: 'https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    maxNativeZoom: 19,
    attributions: [
      MapAttribution('CyclOSM', 'https://www.cyclosm.org'),
      MapAttribution('© OpenStreetMap-Mitwirkende', 'https://www.openstreetmap.org/copyright'),
    ],
    creditsLine: 'CyclOSM (www.cyclosm.org), Kartenserver bereitgestellt von '
        'OpenStreetMap-France. Daten: © OpenStreetMap-Mitwirkende (ODbL).',
    usageNote: 'Kostenloser Dienst auf Spendenbasis ("fair use"), es gilt die '
        'allgemeine OSM-Tile-Usage-Policy: kein Massen-Download, eigener '
        'User-Agent. Bei sehr hoher Nutzung kann der Zugriff eingeschränkt '
        'werden.',
    infoUrl: 'https://operations.osmfoundation.org/policies/tiles/',
    legendUrl: 'https://www.cyclosm.org/legend.html',
    legendHints: [
      'Blau steht für Radverkehr, Grün für Fußgänger und Radfahrer gemeinsam, '
          'Braun für Fußgänger.',
    ],
  );

  final String label;
  final String description;

  /// Kachel-URL-Schablone (`{z}/{x}/{y}`), immer https (Android blockiert
  /// unverschlüsselten Verkehr standardmäßig).
  final String urlTemplate;

  /// Höchste Zoomstufe, für die der Server echte Kacheln liefert.
  final int maxNativeZoom;

  /// Quellenhinweise, wie sie auf der Karte erscheinen.
  final List<MapAttribution> attributions;

  /// Ausführlicher Quellen-/Lizenztext für Einstellungen und Info-Seite.
  final String creditsLine;

  /// Kurzfassung der Nutzungsbedingungen des Kartenanbieters.
  final String usageNote;

  /// Webseite mit den vollständigen Nutzungsbedingungen.
  final String infoUrl;

  /// Seite des Anbieters mit der vollständigen Zeichenerklärung (Legende).
  final String legendUrl;

  /// Kurze, geprüfte Hinweise zum Kartenbild für die Legende in der App
  /// (siehe MapLegendButton) - die vollständige Legende steht unter
  /// [legendUrl].
  final List<String> legendHints;

  /// true: Die Quellenangabe ist Lizenzvoraussetzung und wird deshalb
  /// dauerhaft sichtbar angezeigt (statt hinter dem aufklappbaren
  /// Info-Symbol).
  final bool alwaysVisibleAttribution;

  const MapStyle({
    required this.label,
    required this.description,
    required this.urlTemplate,
    required this.maxNativeZoom,
    required this.attributions,
    required this.creditsLine,
    required this.usageNote,
    required this.infoUrl,
    required this.legendUrl,
    required this.legendHints,
    this.alwaysVisibleAttribution = false,
  });
}
