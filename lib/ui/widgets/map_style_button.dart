import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';

import '../../models/map_style.dart';
import '../../models/route_overlay.dart';
import '../../services/app_preferences.dart';

/// Runder Kartenüberlagerungs-Button zur Wahl der Basiskarte (Standard,
/// OpenTopoMap-R, Reit- und Wanderkarte, ...) sowie des Overlays, das
/// darüber eingeblendet wird (Aus, Wanderrouten, Radrouten, Seemarken) -
/// ersetzt den früheren reinen Landkarte/Seekarte-Umschalter (siehe README
/// Abschnitt 51/60). Die Wahl
/// wird über [AppPreferences] gespeichert und gilt für beide
/// Kartenansichten gemeinsam.
class MapStyleButton extends StatelessWidget {
  final AppPreferences preferences;

  const MapStyleButton({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Karte wählen',
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _showSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.layers, color: Theme.of(context).colorScheme.primary),
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
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoHyphenatingText('Karte', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                RadioGroup<MapStyle>(
                  groupValue: preferences.mapStyle,
                  onChanged: (selected) {
                    if (selected != null) preferences.setMapStyle(selected);
                  },
                  child: Column(
                    children: [
                      for (final style in MapStyle.values)
                        RadioListTile<MapStyle>(
                          contentPadding: EdgeInsets.zero,
                          value: style,
                          title: AutoHyphenatingText(style.label),
                          subtitle: AutoHyphenatingText(style.description),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                AutoHyphenatingText('Einblenden', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                RadioGroup<RouteOverlay>(
                  groupValue: preferences.routeOverlay,
                  onChanged: (selected) {
                    if (selected != null) preferences.setRouteOverlay(selected);
                  },
                  child: Column(
                    children: [
                      for (final overlay in RouteOverlay.values)
                        RadioListTile<RouteOverlay>(
                          contentPadding: EdgeInsets.zero,
                          value: overlay,
                          title: AutoHyphenatingText(overlay.label),
                          subtitle: AutoHyphenatingText(overlay.description),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
