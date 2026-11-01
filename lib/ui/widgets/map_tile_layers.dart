import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/map_style.dart';
import '../../models/route_overlay.dart';
import '../../util/external_link.dart';

/// Eigener, die App klar benennender User-Agent für alle Kachelabrufe.
/// flutter_map setzt allein über `userAgentPackageName` den Wert
// "flutter_map (<Paket>)" - openmaps.fr weist das als Standardwert einer
/// Bibliothek zurück ("does not respect our Usage Policy regarding
/// User-Agent", siehe README Abschnitt 51). Der hier gesetzte Header
/// überschreibt ihn. WICHTIG: Die Header-Map muss VERÄNDERBAR sein (kein
/// `const`) - flutter_map schreibt selbst in diese Map, eine const-Map
/// führt zur Laufzeit zu "Cannot modify unmodifiable map".
const String _tileUserAgent = 'onTour/1.0 (de.clausjbauer.ontour)';

/// Liefert die Standard-Kachel-Ebenen (gewählte Basiskarte, optionales
/// Seemarken-Overlay sowie die Pflicht-Attribution) für alle
/// Kartenansichten dieser App.
///
/// Wird sowohl von der Track-Aufzeichnung (`track_page.dart`) als auch
/// von der Track-Detailansicht (`track_detail_page.dart`) verwendet -
/// eine gemeinsame Stelle statt mehrfacher, leicht abweichender Kopien
/// stellt sicher, dass Cache-Größe, User-Agent (siehe
/// Nutzungsbedingungen der Kartenanbieter) und Attribution überall exakt
/// gleich bleiben.
///
/// NEU (README Abschnitt 51): [mapStyle] wählt die Basiskarte (Standard,
/// OpenTopoMap-R, Reit- und Wanderkarte). Das Seemarken-Overlay lässt sich
/// über jede davon legen. Bei Karten, deren Lizenz eine sichtbare
/// Quellenangabe verlangt ([MapStyle.alwaysVisibleAttribution]), wird diese
/// dauerhaft am Kartenrand angezeigt statt hinter dem Info-Symbol.
///
/// Offline-Verhalten, Seekarten-Einschränkung (kein amtliches
/// Tiefenkarten-Overlay) sowie die bewusste Entscheidung GEGEN
/// vorausschauendes Herunterladen ganzer Regionen sind unverändert wie in
/// README Abschnitt 8/9 beschrieben - das gilt für alle Basiskarten.
List<Widget> buildMapTileLayers({
  required bool nauticalMode,
  MapStyle mapStyle = MapStyle.standard,
  RouteOverlay routeOverlay = RouteOverlay.none,
}) {
  final overlayUrl = routeOverlay.urlTemplate;
  final attributions = <MapAttribution>[
    ...mapStyle.attributions,
    if (overlayUrl != null) ...routeOverlay.attributions,
    if (nauticalMode) const MapAttribution('Seemarken: © OpenSeaMap-Mitwirkende', 'https://www.openseamap.org'),
  ];

  return [
    TileLayer(
      urlTemplate: mapStyle.urlTemplate,
      maxNativeZoom: mapStyle.maxNativeZoom,
      userAgentPackageName: 'de.clausjbauer.ontour',
      tileProvider: NetworkTileProvider(
        headers: {'User-Agent': _tileUserAgent},
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: 300 * 1024 * 1024, // 300 MB
        ),
      ),
    ),
    // NEU (Abschnitt 52): Wander-/Radrouten (transparente Kacheln) über der
    // Basiskarte, unter dem Seemarken-Overlay.
    if (overlayUrl != null)
      TileLayer(
        urlTemplate: overlayUrl,
        maxNativeZoom: routeOverlay.maxNativeZoom,
        userAgentPackageName: 'de.clausjbauer.ontour',
        tileProvider: NetworkTileProvider(
          headers: {'User-Agent': _tileUserAgent},
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 300 * 1024 * 1024,
          ),
        ),
      ),
    if (nauticalMode)
      TileLayer(
        urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
        userAgentPackageName: 'de.clausjbauer.ontour',
        tileProvider: NetworkTileProvider(
          headers: {'User-Agent': _tileUserAgent},
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 300 * 1024 * 1024,
          ),
        ),
      ),
    if (mapStyle.alwaysVisibleAttribution)
      _PermanentAttribution(attributions: attributions)
    else
      RichAttributionWidget(
        attributions: [
          for (final a in attributions)
            TextSourceAttribution(
              a.text,
              prependCopyright: false,
              onTap: () => openExternalLink(a.url),
            ),
        ],
      ),
  ];
}

/// Dauerhaft sichtbare, antippbare Quellenangabe am unteren rechten
/// Kartenrand - für Karten, deren Lizenz die Nennung der Quelle verlangt.
class _PermanentAttribution extends StatelessWidget {
  final List<MapAttribution> attributions;

  const _PermanentAttribution({required this.attributions});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      color: scheme.onSurface,
      decoration: TextDecoration.underline,
    );
    final separatorStyle = TextStyle(fontSize: 11, color: scheme.onSurface);

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Wrap(
              alignment: WrapAlignment.end,
              children: [
                for (var i = 0; i < attributions.length; i++) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openExternalLink(attributions[i].url),
                    child: Text(attributions[i].text, style: style),
                  ),
                  if (i < attributions.length - 1) Text(' · ', style: separatorStyle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
