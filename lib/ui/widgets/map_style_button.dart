import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/map_style.dart';
import '../../models/route_overlay.dart';
import '../../services/app_preferences.dart';

/// Runder Kartenüberlagerungs-Button zur Wahl der Basiskarte sowie des
/// Overlays (Aus, Wanderrouten, Radrouten, Seemarken, Camping), siehe
/// README Abschnitt 51/60.
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
        child: _MapStyleSheet(preferences: preferences),
      ),
    );
  }
}

class _MapStyleSheet extends StatefulWidget {
  final AppPreferences preferences;

  const _MapStyleSheet({required this.preferences});

  @override
  State<_MapStyleSheet> createState() => _MapStyleSheetState();
}

class _MapStyleSheetState extends State<_MapStyleSheet> {
  final ScrollController _scroll = ScrollController();
  late bool _wasCamping = widget.preferences.campingEnabled;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrollt ans Ende, sobald Camping neu gewählt wurde - der Schalter
  /// "Wildcampen einbeziehen" erscheint unten und läge sonst außerhalb des
  /// sichtbaren Bereichs.
  void _scrollDownIfCampingJustSelected(bool nowCamping) {
    if (nowCamping && !_wasCamping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
    _wasCamping = nowCamping;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.preferences;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        _scrollDownIfCampingJustSelected(prefs.campingEnabled);
        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AutoHyphenatingText('Karte', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              RadioGroup<MapStyle>(
                groupValue: prefs.mapStyle,
                onChanged: (selected) {
                  if (selected != null) prefs.setMapStyle(selected);
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
                groupValue: prefs.routeOverlay,
                onChanged: (selected) {
                  if (selected != null) prefs.setRouteOverlay(selected);
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
              // Camping ist der letzte Eintrag der Liste - der Schalter steht
              // deshalb direkt darunter, eingerückt unter dem Radiobutton.
              if (prefs.campingEnabled)
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Wildcampen einbeziehen'),
                    subtitle: const Text('Einfache Zeltplätze ohne Ausstattung'),
                    value: prefs.campingBackcountry,
                    onChanged: prefs.setCampingBackcountry,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
