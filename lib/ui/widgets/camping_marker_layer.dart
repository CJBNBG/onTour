import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

import '../../models/camping_site.dart';
import '../../services/camping_data_service.dart';
import '../../util/external_link.dart';

/// Marker-Ebene für Camping, Stellplätze und Wildcampen. Gehört in die
/// `children` einer FlutterMap. Erst ab [minZoom] sichtbar.
class CampingMarkerLayer extends StatefulWidget {
  final bool includeBackcountry;
  final ValueChanged<CampingSite> onSetDestination;

  const CampingMarkerLayer({
    super.key,
    required this.includeBackcountry,
    required this.onSetDestination,
  });

  static const double minZoom = 9;

  @override
  State<CampingMarkerLayer> createState() => _CampingMarkerLayerState();
}

class _CampingMarkerLayerState extends State<CampingMarkerLayer> {
  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  Future<void> _loadData() async {
    try {
      await CampingDataService.instance.load();
    } catch (_) {
      // Daten nicht ladbar - dann bleibt die Ebene einfach leer.
      return;
    }
    if (mounted) setState(() {});
  }

  static IconData _icon(CampingCategory c) => switch (c) {
        CampingCategory.standard => Icons.holiday_village,
        CampingCategory.caravan => Icons.rv_hookup,
        CampingCategory.backcountry => Icons.forest,
      };

  static Color _color(CampingCategory c) => switch (c) {
        CampingCategory.standard => const Color(0xFF2E7D32),
        CampingCategory.caravan => const Color(0xFF1565C0),
        CampingCategory.backcountry => const Color(0xFF6D4C41),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CampingDataService.instance,
      builder: (context, _) {
        final camera = MapCamera.of(context);
        final service = CampingDataService.instance;
        if (camera.zoom < CampingMarkerLayer.minZoom || !service.isLoaded) {
          return const SizedBox.shrink();
        }
        final sites = service.inBounds(
          camera.visibleBounds,
          includeBackcountry: widget.includeBackcountry,
        );
        return MarkerLayer(
          markers: [
            for (final site in sites)
              Marker(
                point: LatLng(site.latitude, site.longitude),
                width: 34,
                height: 34,
                child: GestureDetector(
                  onTap: () => _showDetails(context, site),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _color(site.category),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 3),
                      ],
                    ),
                    child: Icon(_icon(site.category), size: 18, color: Colors.white),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _yesNo(String? v) => switch (v) {
        'yes' => 'ja',
        'no' => 'nein',
        'customers' => 'nur für Kunden',
        _ => v ?? '',
      };

  void _showDetails(BuildContext context, CampingSite site) {
    final rows = <(String, String)>[
      if (site.operator != null) ('Betreiber', site.operator!),
      if (site.fee != null) ('Gebühr', _yesNo(site.fee)),
      if (site.tents != null) ('Zelte', _yesNo(site.tents)),
      if (site.caravans != null) ('Wohnwagen/Wohnmobile', _yesNo(site.caravans)),
      if (site.dumpStation != null) ('Entsorgung', _yesNo(site.dumpStation)),
      if (site.internetAccess != null) ('Internet', site.internetAccess == 'no' ? 'nein' : site.internetAccess!),
      if (site.internetFee != null) ('Internet kostenpflichtig', _yesNo(site.internetFee)),
      if (site.nudism != null) ('FKK', _yesNo(site.nudism)),
      if (site.phone != null) ('Telefon', site.phone!),
    ];
    final website = site.website;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(site.displayName, style: theme.textTheme.titleLarge),
                Text(site.categoryLabel, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Text(
                    'Zu diesem Eintrag liegen keine weiteren Angaben vor.',
                    style: theme.textTheme.bodySmall,
                  ),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: Text(label, style: theme.textTheme.bodyMedium)),
                        Expanded(
                          flex: 6,
                          child: SelectableText(value, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.place),
                      label: const Text('Als Ziel setzen'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        widget.onSetDestination(site);
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('In OpenCampingMap ansehen'),
                      onPressed: () => openExternalLink(site.openCampingMapUrl),
                    ),
                    if (website != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.language),
                        label: const Text('Website'),
                        onPressed: () => openExternalLink(
                          website.startsWith('http') ? website : 'https://$website',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
