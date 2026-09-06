import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/widgets.dart';

/// Liefert die Standard-Kachel-Ebenen (Landkarte, optionales
/// Seemarken-Overlay sowie die Pflicht-Attribution) für alle
/// Kartenansichten dieser App.
///
/// Wird sowohl von der Track-Aufzeichnung (`track_page.dart`) als auch
/// von der Track-Detailansicht (`track_detail_page.dart`) verwendet -
/// eine gemeinsame Stelle statt mehrfacher, leicht abweichender Kopien
/// stellt sicher, dass Cache-Größe, User-Agent (siehe
/// OpenStreetMap-Nutzungsbedingungen) und Attribution überall exakt
/// gleich bleiben. Ursprünglich war das Teil der inzwischen entfallenen,
/// eigenständigen Kartenseite (`map_page.dart`) - siehe README Abschnitt
/// 9 für die Begründung, warum diese durch die Track-Detailansicht
/// ersetzt wurde.
///
/// Offline-Verhalten, Seekarten-Einschränkung (kein amtliches
/// Tiefenkarten-Overlay) sowie die bewusste Entscheidung GEGEN
/// vorausschauendes Herunterladen ganzer Regionen sind unverändert wie in
/// README Abschnitt 8/9 beschrieben - das gilt jetzt für beide
/// Kartenansichten gleichermaßen.
List<Widget> buildMapTileLayers({required bool nauticalMode}) {
  return [
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'de.clausjbauer.ontour',
      tileProvider: NetworkTileProvider(
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: 300 * 1024 * 1024, // 300 MB
        ),
      ),
    ),
    if (nauticalMode)
      TileLayer(
        urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
        userAgentPackageName: 'de.clausjbauer.ontour',
        tileProvider: NetworkTileProvider(
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 300 * 1024 * 1024,
          ),
        ),
      ),
    RichAttributionWidget(
      attributions: [
        const TextSourceAttribution('© OpenStreetMap-Mitwirkende'),
        if (nauticalMode)
          const TextSourceAttribution('Seemarken: © OpenSeaMap-Mitwirkende'),
      ],
    ),
  ];
}
