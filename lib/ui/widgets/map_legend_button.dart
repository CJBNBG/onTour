import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ontour/models/route_overlay.dart';

import '../../services/app_preferences.dart';
import '../../util/external_link.dart';

/// Runder Kartenüberlagerungs-Button, der die Legende der AKTUELL
/// angezeigten Karte öffnet (siehe README Abschnitt 53): Hinweise zur
/// gewählten Basiskarte, zu einem aktiven Routen- bzw. Seemarken-Overlay und
/// zu den Symbolen der App selbst (Track, Position, Ziel, Start/Ende).
///
/// Die Karten selbst werden von Fremdanbietern als Kacheln geliefert - die
/// Zeichenerklärung dazu pflegen die Anbieter. Deshalb zeigt die App je Karte
/// nur kurze, geprüfte Hinweise und verweist für die vollständige Legende auf
/// die Seite des Anbieters (öffnet im Browser).
class MapLegendButton extends StatelessWidget {
  final AppPreferences preferences;

  const MapLegendButton({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Legende',
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _showSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.legend_toggle, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: preferences,
          builder: (context, _) {
            final theme = Theme.of(context);
            final style = preferences.mapStyle;
            final overlay = preferences.routeOverlay;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoHyphenatingText('Legende', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _section(
                      context,
                      title: style.label,
                      hints: style.legendHints,
                      url: style.legendUrl,
                    ),
                    if (overlay.isActive && overlay != RouteOverlay.camping)
                      _section(
                        context,
                        title: overlay.label,
                        hints: overlay.legendHints,
                        url: overlay.legendUrl,
                      ),
                    const Divider(height: 32),
                    AutoHyphenatingText('Symbole in onTour', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _symbolRow(
                      Container(width: 28, height: 4, color: const Color(0xFFE53935)),
                      'Aufgezeichneter bzw. gespeicherter Track',
                    ),
                    _symbolRow(
                      Icon(Icons.my_location, color: theme.colorScheme.primary),
                      'Aktuelle Position',
                    ),
                    _symbolRow(
                      const Icon(Icons.place, color: Color(0xFFE53935)),
                      'Ziel (Ortssuche oder langes Drücken auf die Karte)',
                    ),
                    _symbolRow(
                      Icon(Icons.trip_origin, color: theme.colorScheme.primary),
                      'Start eines gespeicherten Tracks',
                    ),
                    _symbolRow(
                      Icon(Icons.flag, color: theme.colorScheme.primary),
                      'Ende eines gespeicherten Tracks',
                    ),
                    if (preferences.campingEnabled) ...[
                      const Divider(height: 32),
                      AutoHyphenatingText('Camping und Stellplätze', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _symbolRow(
                        _campingSymbol(Icons.holiday_village, const Color(0xFF2E7D32)),
                        'Campingplatz',
                      ),
                      _symbolRow(
                        _campingSymbol(Icons.rv_hookup, const Color(0xFF1565C0)),
                        'Stellplatz für Wohnmobile',
                      ),
                      if (preferences.campingBackcountry)
                        _symbolRow(
                          _campingSymbol(Icons.forest, const Color(0xFF6D4C41)),
                          'Wildcampen (einfache Zeltplätze ohne Ausstattung)',
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: AutoHyphenatingText(
                          'Marker erscheinen ab Zoomstufe 9. Daten: OpenCampingMap, © OpenStreetMap-Mitwirkende.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<String> hints,
    required String url,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AutoHyphenatingText(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final hint in hints)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: AutoHyphenatingText(hint, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          if (url.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openExternalLink(url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Vollständige Legende öffnen'),
              ),
            ),
        ],
      ),
    );
  }

  /// Kleines rundes Symbol wie auf der Karte (siehe CampingMarkerLayer).
  Widget _campingSymbol(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }

  Widget _symbolRow(Widget symbol, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 36, child: Center(child: symbol)),
          const SizedBox(width: 12),
          Expanded(child: AutoHyphenatingText(text)),
        ],
      ),
    );
  }
}
